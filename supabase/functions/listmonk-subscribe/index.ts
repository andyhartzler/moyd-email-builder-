import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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

  // Get environment variables
  const LISTMONK_URL = Deno.env.get("LISTMONK_URL");
  const LISTMONK_USERNAME = Deno.env.get("LISTMONK_USERNAME");
  const LISTMONK_PASSWORD = Deno.env.get("LISTMONK_PASSWORD");

  // Debug: Check if env vars are set
  console.log("Environment check:", {
    LISTMONK_URL: LISTMONK_URL || "NOT SET",
    LISTMONK_USERNAME: LISTMONK_USERNAME ? "SET" : "NOT SET",
    LISTMONK_PASSWORD: LISTMONK_PASSWORD ? "SET" : "NOT SET",
  });

  if (!LISTMONK_URL || !LISTMONK_USERNAME || !LISTMONK_PASSWORD) {
    console.error("Missing environment variables!");
    return new Response(
      JSON.stringify({ error: "Server configuration error. Please contact support." }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  try {
    const body = await req.json();
    const { name, email, lists, attribs } = body;

    console.log("Request body:", JSON.stringify(body, null, 2));

    // Validation
    if (!email || !name) {
      return new Response(
        JSON.stringify({ error: "Name and email are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!lists || !Array.isArray(lists) || lists.length === 0) {
      return new Response(
        JSON.stringify({ error: "At least one list must be selected" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!attribs?.zip_code || !attribs?.date_of_birth) {
      return new Response(
        JSON.stringify({ error: "Zip code and date of birth are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const auth = btoa(`${LISTMONK_USERNAME}:${LISTMONK_PASSWORD}`);

    // Step 1: Get all lists to map UUIDs to IDs
    console.log("Fetching lists from:", `${LISTMONK_URL}/api/lists`);

    const listsResponse = await fetch(`${LISTMONK_URL}/api/lists?per_page=all`, {
      method: "GET",
      headers: {
        "Authorization": `Basic ${auth}`,
        "Content-Type": "application/json",
      },
    });

    console.log("Lists API status:", listsResponse.status);

    if (!listsResponse.ok) {
      const errorText = await listsResponse.text();
      console.error("Lists API failed:", listsResponse.status, errorText);
      return new Response(
        JSON.stringify({ error: "Failed to connect to mailing list server." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const listsData = await listsResponse.json();
    console.log("Lists data:", JSON.stringify(listsData, null, 2));

    // Map UUIDs to IDs
    const allLists = listsData.data?.results || [];
    const listIds: number[] = [];

    for (const uuid of lists) {
      const foundList = allLists.find((l: any) => l.uuid === uuid);
      if (foundList) {
        listIds.push(foundList.id);
        console.log(`Mapped ${uuid} -> ID ${foundList.id} (${foundList.name})`);
      } else {
        console.warn(`UUID not found: ${uuid}`);
      }
    }

    console.log("Resolved list IDs:", listIds);

    if (listIds.length === 0) {
      return new Response(
        JSON.stringify({ error: "Could not find the selected mailing lists." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Step 2: Check if subscriber exists
    const checkUrl = `${LISTMONK_URL}/api/subscribers?query=subscribers.email='${encodeURIComponent(email)}'`;
    console.log("Checking subscriber:", checkUrl);

    const checkResponse = await fetch(checkUrl, {
      headers: {
        "Authorization": `Basic ${auth}`,
        "Content-Type": "application/json",
      },
    });

    if (!checkResponse.ok) {
      console.error("Check failed:", await checkResponse.text());
      return new Response(
        JSON.stringify({ error: "Failed to check subscription status." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const checkData = await checkResponse.json();
    console.log("Check result:", JSON.stringify(checkData, null, 2));

    let subscriberId: number | null = null;
    let subscriberUUID: string | null = null;

    if (checkData.data?.results?.length > 0) {
      // SUBSCRIBER EXISTS - UPDATE
      const existing = checkData.data.results[0];
      subscriberId = existing.id;
      subscriberUUID = existing.uuid;

      console.log("Updating existing subscriber:", subscriberId);

      const existingListIds = existing.lists?.map((l: any) => l.id) || [];
      const allListIds = [...new Set([...existingListIds, ...listIds])];

      const mergedAttribs = {
        ...existing.attribs,
        ...attribs,
        subscriber_id: existing.uuid,
      };

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
            lists: allListIds,
            attribs: mergedAttribs,
          }),
        }
      );

      if (!updateResponse.ok) {
        console.error("Update failed:", await updateResponse.text());
        return new Response(
          JSON.stringify({ error: "Failed to update subscription." }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      console.log("Subscriber updated");

    } else {
      // NEW SUBSCRIBER - CREATE
      console.log("Creating new subscriber");

      const createPayload = {
        email: email,
        name: name,
        status: "enabled",
        lists: listIds,
        attribs: { ...attribs, subscriber_id: "" },
        preconfirm_subscriptions: false,
      };

      console.log("Create payload:", JSON.stringify(createPayload, null, 2));

      const createResponse = await fetch(`${LISTMONK_URL}/api/subscribers`, {
        method: "POST",
        headers: {
          "Authorization": `Basic ${auth}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(createPayload),
      });

      const createText = await createResponse.text();
      console.log("Create response:", createResponse.status, createText);

      if (!createResponse.ok) {
        if (createText.includes("duplicate") || createText.includes("exists")) {
          return new Response(
            JSON.stringify({ error: "This email is already subscribed." }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        return new Response(
          JSON.stringify({ error: "Failed to create subscription." }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const createData = JSON.parse(createText);
      subscriberId = createData.data?.id;
      subscriberUUID = createData.data?.uuid;

      console.log("Created subscriber:", subscriberId, subscriberUUID);

      // Update with subscriber_id in attribs
      if (subscriberId && subscriberUUID) {
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
              lists: listIds,
              attribs: { ...attribs, subscriber_id: subscriberUUID },
            }),
          }
        );

        // Send opt-in email
        console.log("Sending opt-in email");
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
    console.error("Error:", error);
    return new Response(
      JSON.stringify({ error: "An unexpected error occurred." }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
