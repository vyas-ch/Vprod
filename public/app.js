const rootConfig = window.VPROD_CONFIG || {};
const heroVideo = document.querySelector('#hero-video');
const videoToggle = document.querySelector('#video-toggle');
if (heroVideo && videoToggle && /^\/assets\/[a-zA-Z0-9._-]+\.mp4$/.test(rootConfig.heroVideo || '')) {
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
  let userPaused = false;
  let userStarted = false;
  let inView = true;
  const automatic = () => !reduceMotion.matches && !navigator.connection?.saveData;
  const updateButton = () => {
    const playing = !heroVideo.paused;
    videoToggle.querySelector('span:first-child').textContent = playing ? 'Ⅱ' : '▶';
    videoToggle.querySelector('span:last-child').textContent = playing ? 'Pauzeer achtergrond' : 'Speel achtergrond';
    videoToggle.setAttribute('aria-label', playing ? 'Pauzeer achtergrondvideo' : 'Speel achtergrondvideo');
  };
  async function playBackground() {
    heroVideo.muted = true;
    heroVideo.autoplay = true;
    if (!heroVideo.getAttribute('src')) heroVideo.src = rootConfig.heroVideo;
    try { await heroVideo.play(); } catch { updateButton(); }
  }
  function syncPlayback() {
    if (document.hidden || !inView || userPaused || (!automatic() && !userStarted)) heroVideo.pause();
    else playBackground();
  }
  videoToggle.hidden = false;
  videoToggle.addEventListener('click', () => {
    if (heroVideo.paused) { userPaused = false; userStarted = true; playBackground(); }
    else { userPaused = true; heroVideo.pause(); }
  });
  heroVideo.addEventListener('playing', () => { heroVideo.classList.add('is-playing'); updateButton(); });
  heroVideo.addEventListener('pause', updateButton);
  heroVideo.addEventListener('error', () => { heroVideo.classList.remove('is-playing'); videoToggle.hidden = true; });
  document.addEventListener('visibilitychange', syncPlayback);
  reduceMotion.addEventListener('change', () => { userStarted = false; syncPlayback(); });
  new IntersectionObserver(entries => { inView = entries[0].isIntersecting; syncPlayback(); }, { threshold:0.05 }).observe(heroVideo.closest('.hero'));
  updateButton();
}
const menuButton = document.querySelector('.menu-toggle');
const navigation = document.querySelector('#main-nav');
function closeMenu() { menuButton?.setAttribute('aria-expanded', 'false'); navigation?.classList.remove('is-open'); }
menuButton?.addEventListener('click', () => { const open = menuButton.getAttribute('aria-expanded') !== 'true'; menuButton.setAttribute('aria-expanded', String(open)); navigation.classList.toggle('is-open', open); });
navigation?.querySelectorAll('a').forEach(link => link.addEventListener('click', closeMenu));
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && menuButton?.getAttribute('aria-expanded') === 'true') {
    const focusInMenu = navigation?.contains(document.activeElement);
    closeMenu();
    if (focusInMenu) menuButton.focus();
  }
});
document.addEventListener('pointerdown', event => {
  if (menuButton?.getAttribute('aria-expanded') === 'true' && !menuButton.contains(event.target) && !navigation?.contains(event.target)) closeMenu();
});
document.querySelectorAll('[data-filter]').forEach(button => button.addEventListener('click', () => {
  const category = button.dataset.filter;
  document.querySelectorAll('[data-filter]').forEach(item => { const active = item === button; item.classList.toggle('active', active); item.setAttribute('aria-pressed', String(active)); });
  let visible = 0;
  document.querySelectorAll('[data-category]').forEach(card => { card.hidden = category !== 'Alles' && card.dataset.category !== category; if (!card.hidden) visible++; });
  document.querySelector('#filter-status').textContent = `${visible} ${visible === 1 ? 'mogelijkheid' : 'mogelijkheden'}${category === 'Alles' ? '' : ` voor ${category}`}`;
}));
document.querySelectorAll('[data-service]').forEach(link => link.addEventListener('click', () => {
  document.querySelectorAll('input[name="service"]').forEach(input => { input.checked = input.value === link.dataset.service; });
}));
const email = typeof rootConfig.contactEmail === 'string' && /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(rootConfig.contactEmail) ? rootConfig.contactEmail : '';
document.querySelectorAll('[data-contact-email]').forEach(link => { if (email) { link.textContent = email; link.href = `mailto:${email}`; link.hidden = false; } });
const phone = typeof rootConfig.phone === 'string' ? rootConfig.phone : '';
document.querySelectorAll('[data-contact-phone]').forEach(link => { if (phone) { link.textContent = phone; link.href = `tel:${phone.replace(/[^+\d]/g, '')}`; link.hidden = false; } });
if (email) document.querySelector('#contact-fallback')?.setAttribute('hidden', '');
document.querySelector('#year').textContent = new Date().getFullYear();
const form = document.querySelector('#project-form');
const dialog = document.querySelector('#request-dialog');
form?.addEventListener('submit', event => {
  event.preventDefault();
  if (!form.reportValidity()) return;
  const data = new FormData(form);
  const services = data.getAll('service');
  if (!services.length) { document.querySelector('#form-status').textContent = 'Kies minimaal één dienst: IT, video of audio.'; document.querySelector('input[name="service"]').focus(); return; }
  document.querySelector('#form-status').textContent = '';
  const subject = `Projectaanvraag — ${services.join(', ')}`;
  const body = `Hallo V Production,\n\nIk wil graag een project bespreken.\n\nDiensten: ${services.join(', ')}\nNaam: ${String(data.get('name')).trim()}\nE-mailadres: ${String(data.get('email')).trim()}\n\nMijn idee:\n${String(data.get('message')).trim()}\n\nMet vriendelijke groet,\n${String(data.get('name')).trim()}`;
  document.querySelector('#request-draft').value = body;
  document.querySelector('#copy-status').textContent = '';
  const mailLink = document.querySelector('#email-request');
  if (email) { mailLink.href = `mailto:${email}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`; mailLink.hidden = false; document.querySelector('#request-dialog-description').textContent = 'Open je e-mailprogramma, controleer je aanvraag en verstuur die wanneer je wilt.'; }
  dialog.showModal();
});
document.querySelector('.dialog-close')?.addEventListener('click', () => dialog.close());
dialog?.addEventListener('click', event => { if (event.target === dialog) { const box = dialog.getBoundingClientRect(); if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) dialog.close(); } });
document.querySelector('#copy-request')?.addEventListener('click', async () => {
  const textarea = document.querySelector('#request-draft');
  try { await navigator.clipboard.writeText(textarea.value); document.querySelector('#copy-status').textContent = 'Aanvraag gekopieerd.'; }
  catch { textarea.focus(); textarea.select(); document.querySelector('#copy-status').textContent = 'De tekst is geselecteerd. Gebruik de kopieerfunctie van je apparaat.'; }
});
