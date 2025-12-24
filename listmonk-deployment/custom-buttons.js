// MOYD Custom Buttons - Refresh and Report Problem
// Mobile-optimized with responsive sizing and touch support
(function() {
  'use strict';

  // Detect mobile device
  function isMobile() {
    return window.innerWidth <= 768 ||
           ('ontouchstart' in window) ||
           (navigator.maxTouchPoints > 0);
  }

  // Get responsive button size (minimum 44px for WCAG touch targets)
  function getButtonSize() {
    if (window.innerWidth <= 480) return 48; // Small phones - larger touch targets
    if (window.innerWidth <= 768) return 44; // Tablets/large phones
    return 40; // Desktop
  }

  // Wait for DOM to load
  function init() {
    const menu = document.querySelector('.menu');
    if (!menu) {
      setTimeout(init, 500);
      return;
    }

    // Remove existing buttons if re-initializing (for resize)
    const existing = document.getElementById('moyd-custom-buttons');
    if (existing) existing.remove();

    const buttonSize = getButtonSize();
    const mobile = isMobile();

    // Create buttons container
    const buttonsContainer = document.createElement('div');
    buttonsContainer.id = 'moyd-custom-buttons';
    buttonsContainer.style.cssText = `
      position: fixed;
      top: ${mobile ? '10px' : '15px'};
      left: ${mobile ? '10px' : '15px'};
      z-index: 1000;
      display: flex;
      gap: ${mobile ? '8px' : '10px'};
    `.replace(/\s+/g, ' ').trim();

    // Create refresh button
    const refreshBtn = document.createElement('button');
    refreshBtn.innerHTML = '🔄';
    refreshBtn.title = 'Refresh Page';
    refreshBtn.setAttribute('aria-label', 'Refresh Page');
    refreshBtn.style.cssText = `
      width: ${buttonSize}px;
      height: ${buttonSize}px;
      background-color: #273351;
      border: none;
      border-radius: 8px;
      color: white;
      font-size: ${mobile ? '18px' : '20px'};
      cursor: pointer;
      transition: all 0.3s ease;
      -webkit-tap-highlight-color: transparent;
      touch-action: manipulation;
    `.replace(/\s+/g, ' ').trim();

    // Touch and mouse events for refresh button
    function refreshBtnActive() {
      refreshBtn.style.transform = 'rotate(180deg)';
      refreshBtn.style.backgroundColor = '#1a2438';
    }
    function refreshBtnInactive() {
      refreshBtn.style.transform = 'rotate(0deg)';
      refreshBtn.style.backgroundColor = '#273351';
    }

    refreshBtn.addEventListener('mouseenter', refreshBtnActive);
    refreshBtn.addEventListener('mouseleave', refreshBtnInactive);
    refreshBtn.addEventListener('touchstart', refreshBtnActive, { passive: true });
    refreshBtn.addEventListener('touchend', refreshBtnInactive, { passive: true });
    refreshBtn.addEventListener('click', function(e) {
      e.preventDefault();
      location.reload();
    });

    // Create report problem button
    const reportBtn = document.createElement('button');
    reportBtn.innerHTML = '?';
    reportBtn.title = 'Report a Problem';
    reportBtn.setAttribute('aria-label', 'Report a Problem');
    reportBtn.style.cssText = `
      width: ${buttonSize}px;
      height: ${buttonSize}px;
      background-color: #273351;
      border: none;
      border-radius: 8px;
      color: white;
      font-size: ${mobile ? '22px' : '24px'};
      font-weight: bold;
      cursor: pointer;
      transition: background-color 0.3s ease;
      -webkit-tap-highlight-color: transparent;
      touch-action: manipulation;
    `.replace(/\s+/g, ' ').trim();

    // Touch and mouse events for report button
    function reportBtnActive() {
      reportBtn.style.backgroundColor = '#1a2438';
    }
    function reportBtnInactive() {
      reportBtn.style.backgroundColor = '#273351';
    }

    reportBtn.addEventListener('mouseenter', reportBtnActive);
    reportBtn.addEventListener('mouseleave', reportBtnInactive);
    reportBtn.addEventListener('touchstart', reportBtnActive, { passive: true });
    reportBtn.addEventListener('touchend', reportBtnInactive, { passive: true });
    reportBtn.addEventListener('click', function(e) {
      e.preventDefault();
      showReportModal();
    });

    // Add buttons to container
    buttonsContainer.appendChild(refreshBtn);
    buttonsContainer.appendChild(reportBtn);
    document.body.appendChild(buttonsContainer);

    // Adjust menu margin (responsive)
    menu.style.marginTop = mobile ? '15px' : '20px';
  }

  // Create and show report modal (mobile-optimized)
  function showReportModal() {
    // Remove existing modal if any
    const existing = document.getElementById('moyd-report-modal');
    if (existing) existing.remove();

    const mobile = isMobile();
    const smallPhone = window.innerWidth <= 480;

    // Create modal overlay
    const modal = document.createElement('div');
    modal.id = 'moyd-report-modal';
    modal.style.cssText = `
      position: fixed;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      background: rgba(0,0,0,0.5);
      display: flex;
      align-items: center;
      justify-content: center;
      z-index: 10000;
      padding: ${mobile ? '16px' : '20px'};
      box-sizing: border-box;
    `.replace(/\s+/g, ' ').trim();

    // Create modal content
    const modalContent = document.createElement('div');
    modalContent.style.cssText = `
      background: white;
      padding: ${smallPhone ? '20px' : mobile ? '25px' : '30px'};
      border-radius: 12px;
      width: 100%;
      max-width: ${mobile ? '100%' : '500px'};
      max-height: 90vh;
      overflow-y: auto;
      box-shadow: 0 4px 20px rgba(0,0,0,0.3);
      -webkit-overflow-scrolling: touch;
    `.replace(/\s+/g, ' ').trim();

    // Contact button styles (responsive)
    const contactBtnStyle = `
      flex: ${smallPhone ? '1 1 100%' : '1'};
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: ${mobile ? '16px 12px' : '20px'};
      background: #273351;
      color: white;
      text-decoration: none;
      border-radius: 8px;
      transition: background 0.3s;
      min-height: 44px;
      -webkit-tap-highlight-color: transparent;
      touch-action: manipulation;
    `.replace(/\s+/g, ' ').trim();

    // Modal HTML with responsive styles
    modalContent.innerHTML = `
      <h2 style="margin: 0 0 10px 0; color: #273351; font-size: ${smallPhone ? '20px' : '24px'};">Report a Problem</h2>
      <p style="margin: 0 0 ${mobile ? '20px' : '25px'} 0; color: #666; font-size: ${smallPhone ? '13px' : '14px'};">
        Having an issue? Contact Andrew directly via text message or email.
      </p>
      <div style="display: flex; flex-wrap: wrap; gap: ${mobile ? '12px' : '15px'}; margin-bottom: ${mobile ? '16px' : '20px'};">
        <a href="sms:+18168983612&body=Hey%20Andrew%2C%20I%27m%20currently%20having%20a%20problem%20with%20the%20email%20campaign%20feature%20on%20moyd.app.%20"
           style="${contactBtnStyle}"
           id="moyd-sms-btn">
          <span style="font-size: ${smallPhone ? '28px' : '32px'}; margin-bottom: ${mobile ? '8px' : '10px'};">💬</span>
          <span style="font-size: ${smallPhone ? '14px' : '16px'}; font-weight: bold;">Send Text</span>
          <span style="font-size: ${smallPhone ? '11px' : '12px'}; margin-top: 5px; opacity: 0.9;">816-898-3612</span>
        </a>
        <a href="mailto:andrew@moyoungdemocrats.org?subject=MOYD%20App%20Issue&body=Hey%20Andrew%2C%0A%0AI%27m%20currently%20having%20a%20problem%20with%20the%20email%20campaign%20feature%20on%20moyd.app.%0A%0ADetails%3A%0A"
           style="${contactBtnStyle}"
           id="moyd-email-btn">
          <span style="font-size: ${smallPhone ? '28px' : '32px'}; margin-bottom: ${mobile ? '8px' : '10px'};">✉️</span>
          <span style="font-size: ${smallPhone ? '14px' : '16px'}; font-weight: bold;">Send Email</span>
          <span style="font-size: ${smallPhone ? '11px' : '12px'}; margin-top: 5px; opacity: 0.9;">andrew@moyoungdemocrats.org</span>
        </a>
      </div>
      <button id="moyd-close-modal-btn"
              style="width: 100%; padding: ${mobile ? '14px' : '12px'}; background: #e0e0e0; border: none; border-radius: 8px; color: #333; font-size: ${smallPhone ? '15px' : '14px'}; cursor: pointer; transition: background 0.3s; min-height: 44px; -webkit-tap-highlight-color: transparent; touch-action: manipulation;">
        Close
      </button>
    `;

    modal.appendChild(modalContent);

    // Add touch/mouse event handlers after DOM insertion
    document.body.appendChild(modal);

    // Contact button hover/touch effects
    const smsBtn = document.getElementById('moyd-sms-btn');
    const emailBtn = document.getElementById('moyd-email-btn');
    const closeBtn = document.getElementById('moyd-close-modal-btn');

    function setupButtonEvents(btn, activeColor, inactiveColor) {
      btn.addEventListener('mouseenter', function() { this.style.backgroundColor = activeColor; });
      btn.addEventListener('mouseleave', function() { this.style.backgroundColor = inactiveColor; });
      btn.addEventListener('touchstart', function() { this.style.backgroundColor = activeColor; }, { passive: true });
      btn.addEventListener('touchend', function() { this.style.backgroundColor = inactiveColor; }, { passive: true });
    }

    setupButtonEvents(smsBtn, '#1a2438', '#273351');
    setupButtonEvents(emailBtn, '#1a2438', '#273351');
    setupButtonEvents(closeBtn, '#d0d0d0', '#e0e0e0');

    closeBtn.addEventListener('click', function(e) {
      e.preventDefault();
      modal.remove();
    });

    // Close modal when clicking outside
    modal.addEventListener('click', function(e) {
      if (e.target === modal) {
        modal.remove();
      }
    });

    // Close modal on Escape key
    function handleEscape(e) {
      if (e.key === 'Escape') {
        modal.remove();
        document.removeEventListener('keydown', handleEscape);
      }
    }
    document.addEventListener('keydown', handleEscape);

    // Prevent body scroll when modal is open (mobile)
    document.body.style.overflow = 'hidden';
    modal.addEventListener('remove', function() {
      document.body.style.overflow = '';
    });

    // Focus trap for accessibility
    closeBtn.focus();
  }

  // Initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  // Re-initialize on resize (debounced)
  let resizeTimeout;
  window.addEventListener('resize', function() {
    clearTimeout(resizeTimeout);
    resizeTimeout = setTimeout(init, 250);
  });

  // Re-initialize on orientation change
  window.addEventListener('orientationchange', function() {
    setTimeout(init, 100);
  });
})();
