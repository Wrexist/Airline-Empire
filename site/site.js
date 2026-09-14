(() => {
  'use strict';
  const root = document.documentElement;
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let motionPaused = reduceMotion.matches;
  const motionButton = document.querySelector('.motion-toggle');
  function updateMotion() {
    root.classList.toggle('motion-paused', motionPaused);
    if (motionButton) {
      motionButton.disabled = reduceMotion.matches;
      motionButton.setAttribute('aria-pressed', String(motionPaused));
      motionButton.textContent = reduceMotion.matches ? 'Reduced motion enabled' : motionPaused ? 'Resume site motion' : 'Pause site motion';
    }
  }
  motionButton?.addEventListener('click', () => { motionPaused = !motionPaused; updateMotion(); });
  reduceMotion.addEventListener('change', event => { motionPaused = event.matches; updateMotion(); });
  updateMotion();
  if ('IntersectionObserver' in window && !reduceMotion.matches) {
    root.classList.add('motion-ready');
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        observer.unobserve(entry.target);
      }
    }, { threshold: .08, rootMargin: '0px 0px 30px 0px' });
    document.querySelectorAll('.reveal').forEach(element => observer.observe(element));
  }

  const views = {
    routes: { image: 'game-route.webp', alt: 'Route detail showing fares, demand, operations and monthly results.', kicker: 'THE ROUTE DESK', caption: 'Your next opportunity, explained.' },
    fleet: { image: 'game-fleet.webp', alt: 'Actual fleet screen with aircraft status, maintenance and fleet performance.', kicker: 'YOUR FLEET, AT A GLANCE', caption: 'Find the right aircraft for what’s next.' },
    finance: { image: 'game-finance.webp', alt: 'Actual finance screen with cash, revenue, costs and monthly profit charts.', kicker: 'THE BIGGER PICTURE', caption: 'See how a good plan adds up.' }
  };
  const tabs = [...document.querySelectorAll('.gameplay-tab')];
  const gameImage = document.querySelector('#gameplay-image');
  let imageRequest = 0;
  function chooseView(tab) {
    const view = views[tab.dataset.view];
    if (!view || !gameImage) return;
    tabs.forEach(item => { const active = item === tab; item.setAttribute('aria-selected', String(active)); item.tabIndex = active ? 0 : -1; });
    document.querySelector('#gameplay-panel').setAttribute('aria-labelledby', tab.id);
    document.querySelector('#gameplay-kicker').textContent = view.kicker;
    document.querySelector('#gameplay-caption').textContent = view.caption;
    const request = ++imageRequest;
    gameImage.src = 'assets/web/' + view.image;
    gameImage.alt = view.alt;
    gameImage.classList.remove('image-switch');
    gameImage.decode().then(() => {
      if (request === imageRequest && !motionPaused) gameImage.classList.add('image-switch');
    }).catch(() => {});
  }
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => chooseView(tab));
    tab.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowDown' || event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      if (event.key === 'ArrowUp' || event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
      if (event.key === 'Home') next = 0;
      if (event.key === 'End') next = tabs.length - 1;
      if (next !== undefined) { event.preventDefault(); tabs[next].focus(); chooseView(tabs[next]); }
    });
  });

  const orbit = document.querySelector('.plane-orbit');
  const speeds = [...document.querySelectorAll('[data-speed]')];
  speeds.forEach(button => button.addEventListener('click', () => {
    const speed = Number(button.dataset.speed);
    speeds.forEach(item => item.setAttribute('aria-pressed', String(item === button)));
    document.querySelector('.pace-visual').classList.toggle('pace-paused', speed === 0);
    // Keep the decorative motion gentle even at the game's fastest speed.
    const duration = { 1: 18000, 4: 10000, 16: 5000 }[speed];
    const animation = orbit?.getAnimations()[0];
    if (animation && duration) animation.updatePlaybackRate(18000 / duration);
    document.querySelector('#pace-status').textContent = speed === 0 ? 'A little breathing room. Your next move can wait.' : `${speed}× selected. ${speed === 1 ? 'Enjoy the journey.' : 'Watch your plans take flight.'} Website animation only.`;
  }));

  const rail = document.querySelector('#screenshot-rail');
  const previous = document.querySelector('#gallery-prev');
  const next = document.querySelector('#gallery-next');
  function syncRail() {
    if (!rail) return;
    previous.disabled = rail.scrollLeft < 4;
    next.disabled = rail.scrollLeft >= rail.scrollWidth - rail.clientWidth - 4;
  }
  function moveRail(direction) { rail?.scrollBy({ left: direction * Math.max(260, rail.clientWidth * .65), behavior: motionPaused ? 'instant' : 'smooth' }); }
  previous?.addEventListener('click', () => moveRail(-1));
  next?.addEventListener('click', () => moveRail(1));
  rail?.addEventListener('scroll', syncRail, { passive: true });
  window.addEventListener('resize', syncRail, { passive: true });
  syncRail();

  const dialog = document.querySelector('.screenshot-dialog');
  const cards = [...document.querySelectorAll('.screenshot-card')];
  let selected = 0;
  function displayShot(index) {
    selected = (index + cards.length) % cards.length;
    const source = cards[selected].querySelector('img');
    const target = document.querySelector('#dialog-image');
    target.src = source.src;
    target.alt = source.alt;
    document.querySelector('#dialog-count').textContent = `${selected + 1} / ${cards.length}`;
  }
  cards.forEach((card, index) => card.addEventListener('click', () => {
    displayShot(index);
    dialog.showModal();
    root.classList.add('modal-open');
  }));
  document.querySelector('.dialog-close')?.addEventListener('click', () => dialog.close());
  document.querySelector('.dialog-prev')?.addEventListener('click', () => displayShot(selected - 1));
  document.querySelector('.dialog-next')?.addEventListener('click', () => displayShot(selected + 1));
  dialog?.addEventListener('close', () => root.classList.remove('modal-open'));
  dialog?.addEventListener('click', event => {
    const rect = dialog.getBoundingClientRect();
    if (event.target === dialog && (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom)) dialog.close();
  });
  dialog?.addEventListener('keydown', event => {
    if (event.key === 'ArrowRight' || event.key === 'ArrowLeft') {
      event.preventDefault(); displayShot(selected + (event.key === 'ArrowRight' ? 1 : -1));
    }
  });
})();
