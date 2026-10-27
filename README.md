# Massachusetts School Opportunity

Research website examining school socioeconomic composition, FAFSA completion, and educational outcomes across Massachusetts, with a focus on Boston. It preserves school-level uncertainty, source limitations, and the distinction between association and causation.

## Edit and build

The React source is in `src/`. Research data, downloadable analysis exports, and illustrations are in `public/`. The prebuilt site is in `docs/`.

Use Node.js 22.12 or later and npm:

```sh
npm ci
npm run dev
```

After editing:

```sh
npm run build
npm run preview
```

Commit both source changes and the rebuilt `docs/` folder. The build is entirely static; no backend or API key is required. Routes use URL hashes and asset URLs are relative, so the same build works at the repository path or a custom domain. `public/.nojekyll` is copied into `docs/` during every build.

## Enable GitHub Pages

1. Open this repository's **Settings → Pages**.
2. Under **Build and deployment → Source**, choose **Deploy from a branch**.
3. Choose **main** and **/docs**, then click **Save**.
4. Wait for the Pages deployment to finish and use the URL shown in those settings.

The expected project address is `https://bean0623.github.io/ma-fafsa-school-opportunity/`, but it is not live until Pages is enabled and deployment succeeds. Pages for a private repository requires a qualifying GitHub plan; public repositories can use Pages on GitHub Free. Do not change the repository's visibility solely to follow these instructions without reviewing that choice.

## Use a custom domain

After the project URL works, enter your owned domain in **Settings → Pages → Custom domain** and save it. Configure the domain's DNS using [GitHub's current custom-domain instructions](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site), then enable **Enforce HTTPS** once available. No domain has been assumed or configured in this repository.

If GitHub creates `docs/CNAME`, copy that same file to `public/CNAME` before the next build so the custom domain survives rebuilding. Keep the relative Vite base unchanged; this build supports both a project URL and a domain root.

## Research and replication

The website's **Data & code** page includes the source audit, chart data, model exports, data dictionary, and portable Stata analysis scripts. Replication requires the documented source files and Stata. The policy memo remains the author's separate work; the website currently links to recommendations and supporting research.
