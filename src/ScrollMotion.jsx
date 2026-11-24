import { useEffect, useRef } from 'react';
import './motion.css';

// Animate content boundaries, never the individual marks or rows inside a chart.
const REVEAL_TARGETS = [
  '.page-head', '.section > .section-head', '.section > p',
  '.two-col > *', '.impact-grid > *', '.evidence-bridge > *',
  '.home-chart-panel', '.home-recommendation > *', '.home-evidence > h2',
  '.home-evidence-grid > article', '.home-further',
  '.reading-column > section', '.download-row', '.source-row',
  '.section > .table-wrap', '.section > .stat-row', '.section > .callout',
  '.action-stages > article', '.policy-priorities > article', '.policy-next',
  '.beyond-intro', '.beyond-priority > header', '.beyond-priority > .chart-frame',
  '.beyond-priority > .beyond-finding', '.beyond-action', '.beyond-evidence',
  '.beyond-resources', '.beyond-interpretation', '.beyond-next',
  '.se-section-heading', '.se-filters', '.se-table-scroll', '.se-relationship',
].join(',');

const STAGGER_GROUPS = '.two-col,.impact-grid,.evidence-bridge,.home-chart-grid,.home-evidence-grid,.action-stages,.policy-priorities';
const DATA_CONTENT = '.chart-panel,.home-chart-panel,.chart-frame,.table-wrap,.se-table-scroll,.se-relationship';
const clamp = value => Math.max(0, Math.min(1, value));

export function ScrollMotion({ route, ready }) {
  const seen = useRef(new WeakSet());

  useEffect(() => {
    const main = document.getElementById('main');
    if (!main || !window.matchMedia) return undefined;
    const preference = window.matchMedia('(prefers-reduced-motion: reduce)');
    let stopMotion = () => {};

    const configure = () => {
      stopMotion();
      stopMotion = () => {};
      if (preference.matches || !('IntersectionObserver' in window)) return;

      const root = document.documentElement;
      const targets = [...main.querySelectorAll(REVEAL_TARGETS)].filter(element =>
        !element.closest('details') && !element.parentElement?.closest(REVEAL_TARGETS)
      );
      const reveal = element => {
        seen.current.add(element);
        element.classList.add('motion-visible');
        observer.unobserve(element);
      };
      const observer = new IntersectionObserver(entries => {
        entries.forEach(entry => {
          if (entry.isIntersecting) reveal(entry.target);
        });
      }, { rootMargin: '0px 0px -36px 0px', threshold: 0 });

      root.classList.add('motion-enabled');
      targets.forEach(element => {
        element.classList.add('motion-reveal');
        if (element.matches(DATA_CONTENT) || element.querySelector('.chart-frame,table')) {
          element.classList.add('motion-data');
        }
        const siblings = element.parentElement?.matches(STAGGER_GROUPS)
          ? [...element.parentElement.children].filter(child => targets.includes(child))
          : [];
        element.style.setProperty('--reveal-delay', `${Math.max(0, siblings.indexOf(element)) * 80}ms`);
        // Anything already on screen remains immediately readable. Only content
        // below the fold is staged; each element reveals once per mount.
        if (seen.current.has(element) || element.getBoundingClientRect().top < window.innerHeight - 12) {
          reveal(element);
        } else {
          observer.observe(element);
        }
      });

      const onFocus = event => {
        let element = event.target instanceof Element ? event.target.closest('.motion-reveal') : null;
        while (element && main.contains(element)) {
          reveal(element);
          element = element.parentElement?.closest('.motion-reveal');
        }
      };
      main.addEventListener('focusin', onFocus);

      const hero = main.querySelector('.home-hero');
      const photo = hero?.querySelector('.hero-art');
      let frame = 0;
      const updatePhoto = () => {
        frame = 0;
        if (!hero || !photo) return;
        // Read layout offsets rather than the animated bounding box, so the
        // translation cannot feed back into its own scroll calculation. This
        // also keeps the stacked mobile photo crisp as it first comes into view.
        let documentTop = 0;
        for (let node = photo; node; node = node.offsetParent) {
          documentTop += node.offsetTop;
          if (node.offsetParent) documentTop += node.offsetParent.clientTop;
        }
        const photoTop = documentTop - window.scrollY;
        const progress = clamp(-photoTop / Math.max(1, photo.offsetHeight * 0.9));
        // Soften only when the photo itself leaves the top of the viewport.
        // No scale/crop is applied, and a fully visible photo stays sharp.
        photo.style.setProperty('--hero-shift', `${(progress * 26).toFixed(2)}px`);
        photo.style.setProperty('--hero-softness', `${(progress * progress * 3).toFixed(2)}px`);
        photo.style.setProperty('--hero-visibility', (1 - progress * 0.35).toFixed(3));
      };
      const schedulePhoto = () => {
        if (!frame) frame = window.requestAnimationFrame(updatePhoto);
      };
      if (photo) {
        updatePhoto();
        window.addEventListener('scroll', schedulePhoto, { passive: true });
        window.addEventListener('resize', schedulePhoto);
      }

      stopMotion = () => {
        observer.disconnect();
        main.removeEventListener('focusin', onFocus);
        window.removeEventListener('scroll', schedulePhoto);
        window.removeEventListener('resize', schedulePhoto);
        window.cancelAnimationFrame(frame);
        root.classList.remove('motion-enabled');
        targets.forEach(element => {
          element.classList.remove('motion-reveal', 'motion-visible', 'motion-data');
          element.style.removeProperty('--reveal-delay');
        });
        ['--hero-shift', '--hero-softness', '--hero-visibility'].forEach(property => photo?.style.removeProperty(property));
      };
    };

    configure();
    preference.addEventListener?.('change', configure);
    if (!preference.addEventListener) preference.addListener?.(configure);
    return () => {
      stopMotion();
      preference.removeEventListener?.('change', configure);
      if (!preference.removeEventListener) preference.removeListener?.(configure);
    };
  }, [route, ready]);

  return null;
}
