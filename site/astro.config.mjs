import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// Adresse publique du site. À changer ici le jour où le nom de domaine est acheté.
const site = process.env.SITE_URL ?? 'https://foulove.vercel.app';

export default defineConfig({
  site,
  trailingSlash: 'always',
  build: { format: 'directory', inlineStylesheets: 'auto' },
  integrations: [sitemap({ filter: (page) => !page.includes('/404') })],
  markdown: { smartypants: false },
  // Aucun script en ligne dans les pages : la politique de sécurité (vercel.json) n'autorise que les fichiers du site.
  vite: { build: { assetsInlineLimit: 0 } },
});
