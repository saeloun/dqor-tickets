(() => {
  const eventView = document.getElementById('event-view');
  const passView = document.getElementById('pass-view');
  const dialog = document.getElementById('registration');
  const name = document.getElementById('guest-name');
  const render = () => {
    const pass = location.hash === '#pass';
    eventView.hidden = pass;
    passView.hidden = !pass;
    document.title = pass ? 'Sample pass · Deccan After Hours' : 'Deccan After Hours · DQOR design preview';
    document.getElementById('open-pass').hidden = pass;
    window.scrollTo(0, 0);
    const target = pass ? document.getElementById('back-event') : document.getElementById('rsvp-button');
    if (document.activeElement === document.body || document.activeElement?.closest('[hidden]')) target.focus({preventScroll:true});
  };
  document.getElementById('open-pass').addEventListener('click', () => { location.hash = 'pass'; });
  document.getElementById('back-event').addEventListener('click', () => { location.hash = 'event'; });
  document.getElementById('rsvp-button').addEventListener('click', () => { dialog.showModal(); name.focus(); name.select(); });
  document.getElementById('close-registration').addEventListener('click', () => dialog.close());
  document.getElementById('registration-form').addEventListener('submit', event => {
    event.preventDefault();
    if (!name.value.trim()) { name.setCustomValidity('Enter a sample name.'); name.reportValidity(); return; }
    document.getElementById('pass-name').textContent = name.value.trim();
    dialog.close();
    location.hash = 'pass';
  });
  name.addEventListener('input', () => name.setCustomValidity(''));
  window.addEventListener('hashchange', render);
  if (location.hash === '#pass') render();
})();
