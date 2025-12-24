/* MOYD Public Pages JavaScript */

document.addEventListener('DOMContentLoaded', function() {
  // Add smooth transitions
  document.body.style.opacity = '0';
  setTimeout(function() {
    document.body.style.transition = 'opacity 0.3s ease';
    document.body.style.opacity = '1';
  }, 50);

  // Form validation enhancement
  var forms = document.querySelectorAll('form');
  forms.forEach(function(form) {
    form.addEventListener('submit', function(e) {
      var submitBtn = form.querySelector('button[type="submit"]');
      if (submitBtn) {
        submitBtn.disabled = true;
        submitBtn.textContent = 'Processing...';
      }
    });
  });

  // Checkbox select all/none helpers
  var listOptions = document.querySelector('.list-options');
  if (listOptions && listOptions.querySelectorAll('input[type="checkbox"]').length > 3) {
    var controls = document.createElement('div');
    controls.style.marginBottom = '12px';
    controls.innerHTML = '<a href="#" class="select-all" style="font-size:13px;color:#32A6DE;">Select All</a> | <a href="#" class="select-none" style="font-size:13px;color:#32A6DE;">Select None</a>';
    listOptions.parentNode.insertBefore(controls, listOptions);

    controls.querySelector('.select-all').addEventListener('click', function(e) {
      e.preventDefault();
      listOptions.querySelectorAll('input[type="checkbox"]').forEach(function(cb) { cb.checked = true; });
    });

    controls.querySelector('.select-none').addEventListener('click', function(e) {
      e.preventDefault();
      listOptions.querySelectorAll('input[type="checkbox"]').forEach(function(cb) { cb.checked = false; });
    });
  }
});
