const overview = document.querySelector('[data-vjobs-overview]');

if (overview) {
  const filters = overview.querySelector('[data-vjobs-filters]');
  const buttons = [...overview.querySelectorAll('[data-vjobs-filter]')];
  const cards = [...overview.querySelectorAll('[data-vjobs-category]')];
  const status = overview.querySelector('#vjobs-result');
  const empty = overview.querySelector('[data-vjobs-empty]');
  const emptyCategory = overview.querySelector('[data-vjobs-empty-category]');

  function showCategory(category) {
    let visible = 0;
    for (const card of cards) {
      const show = category === 'Alles' || card.dataset.vjobsCategory === category;
      card.hidden = !show;
      if (show) visible++;
    }
    for (const button of buttons) {
      button.setAttribute('aria-pressed', String(button.dataset.vjobsFilter === category));
    }
    status.textContent = `${visible} ${visible === 1 ? 'project' : 'projecten'}${category === 'Alles' ? '' : ` in ${category}`}`;
    empty.hidden = visible !== 0;
    emptyCategory.textContent = category.toLowerCase();
  }

  for (const button of buttons) {
    button.addEventListener('click', () => showCategory(button.dataset.vjobsFilter));
  }
  overview.querySelector('[data-vjobs-reset]')?.addEventListener('click', () => {
    showCategory('Alles');
    buttons.find(button => button.dataset.vjobsFilter === 'Alles')?.focus();
  });
  filters.hidden = false;
}
