import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const LISTMONK_URL = Deno.env.get("LISTMONK_URL") || "https://mail.moyd.app";
const LISTMONK_USERNAME = Deno.env.get("LISTMONK_USERNAME")!;
const LISTMONK_PASSWORD = Deno.env.get("LISTMONK_PASSWORD")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Helper to get list IDs from UUIDs
async function getListIdFromUUID(uuid: string, auth: string): Promise<number | null> {
  try {
    const response = await fetch(`${LISTMONK_URL}/api/lists`, {
      headers: {
        "Authorization": `Basic ${auth}`,
        "Content-Type": "application/json",
      },
    });

    if (!response.ok) return null;

    const data = await response.json();
    const list = data.data?.results?.find((l: any) => l.uuid === uuid);
    return list?.id || null;
  } catch (error) {
    console.error("Error fetching list:", error);
    return null;
  }
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  try {
    const body = await req.json();
    const { name, email, lists, attribs } = body;

    console.log("Received subscription request:", { name, email, lists: lists?.length, attribs: Object.keys(attribs || {}) });

    // Validation
    if (!email || !name) {
      return new Response(
        JSON.stringify({ error: "Name and email are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!lists || lists.length === 0) {
      return new Response(
        JSON.stringify({ error: "At least one list must be selected" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Validate required attributes
    if (!attribs?.zip_code || !attribs?.date_of_birth) {
      return new Response(
        JSON.stringify({ error: "Zip code and date of birth are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const auth = btoa(`${LISTMONK_USERNAME}:${LISTMONK_PASSWORD}`);

    // Convert list UUIDs to IDs (needed for authenticated API)
    const listIds: number[] = [];
    for (const uuid of lists) {
      const id = await getListIdFromUUID(uuid, auth);
      if (id) listIds.push(id);
    }

    console.log("Resolved list IDs:", listIds);

    // Check if subscriber already exists
    const checkResponse = await fetch(
      `${LISTMONK_URL}/api/subscribers?query=subscribers.email='${encodeURIComponent(email)}'`,
      {
        headers: {
          "Authorization": `Basic ${auth}`,
          "Content-Type": "application/json",
        },
      }
    );

    if (!checkResponse.ok) {
      console.error("Failed to check subscriber:", await checkResponse.text());
      throw new Error("Failed to check if subscriber exists");
    }

    const checkData = await checkResponse.json();
    let subscriberId: number | null = null;
    let subscriberUUID: string | null = null;

    if (checkData.data?.results?.length > 0) {
      // ===== SUBSCRIBER EXISTS - UPDATE =====
      const existing = checkData.data.results[0];
      subscriberId = existing.id;
      subscriberUUID = existing.uuid;

      console.log("Subscriber exists, updating:", subscriberId);

      // Get existing list IDs to preserve them
      const existingListIds = existing.lists?.map((l: any) => l.id) || [];

      // Merge list IDs (keep existing + add new)
      const allListIds = [...new Set([...existingListIds, ...listIds])];

      // Merge new attributes with existing
      const mergedAttribs = {
        ...existing.attribs,
        ...attribs,
        subscriber_id: existing.uuid,
      };

      // Update subscriber - MUST include lists or they get removed!
      const updateResponse = await fetch(
        `${LISTMONK_URL}/api/subscribers/${subscriberId}`,
        {
          method: "PUT",
          headers: {
            "Authorization": `Basic ${auth}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            email: email,
            name: name,
            status: existing.status,
            lists: allListIds,  // CRITICAL: Include lists!
            attribs: mergedAttribs,
          }),
        }
      );

      if (!updateResponse.ok) {
        const errorText = await updateResponse.text();
        console.error("Failed to update subscriber:", errorText);
        throw new Error(`Failed to update subscriber: ${errorText}`);
      }

      console.log("Subscriber updated successfully");

    } else {
      // ===== NEW SUBSCRIBER - CREATE =====
      console.log("Creating new subscriber");

      // Build attributes with subscriber_id placeholder (will update after creation)
      const initialAttribs = {
        ...attribs,
        subscriber_id: "", // Will be set after we get the UUID
      };

      // Create subscriber via authenticated API (allows setting attributes)
      const createResponse = await fetch(`${LISTMONK_URL}/api/subscribers`, {
        method: "POST",
        headers: {
          "Authorization": `Basic ${auth}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          email: email,
          name: name,
          status: "enabled",
          lists: listIds,
          attribs: initialAttribs,
          preconfirm_subscriptions: false, // Require double opt-in
        }),
      });

      if (!createResponse.ok) {
        const errorText = await createResponse.text();
        console.error("Failed to create subscriber:", errorText);

        // Check if it's a duplicate email error
        if (errorText.includes("duplicate") || errorText.includes("exists")) {
          return new Response(
            JSON.stringify({ error: "This email is already subscribed." }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }

        throw new Error(`Failed to create subscriber: ${errorText}`);
      }

      const createData = await createResponse.json();
      subscriberId = createData.data?.id;
      subscriberUUID = createData.data?.uuid;

      console.log("Subscriber created:", subscriberId, subscriberUUID);

      // Update with correct subscriber_id in attributes
      if (subscriberId && subscriberUUID) {
        const finalAttribs = {
          ...attribs,
          subscriber_id: subscriberUUID,
        };

        await fetch(
          `${LISTMONK_URL}/api/subscribers/${subscriberId}`,
          {
            method: "PUT",
            headers: {
              "Authorization": `Basic ${auth}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              email: email,
              name: name,
              status: "enabled",
              lists: listIds,  // CRITICAL: Include lists!
              attribs: finalAttribs,
            }),
          }
        );

        // Send opt-in email
        await fetch(
          `${LISTMONK_URL}/api/subscribers/${subscriberId}/optin`,
          {
            method: "POST",
            headers: {
              "Authorization": `Basic ${auth}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({}),
          }
        );

        console.log("Opt-in email sent");
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: "Please check your email to confirm your subscription.",
        subscriber_id: subscriberId,
        subscriber_uuid: subscriberUUID,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Subscription error:", error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : "An error occurred. Please try again." }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
