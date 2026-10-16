// Bundles src/ into prototype.html (a full page you can open locally) and, with --fragment <path>,
// a fragment without the document skeleton for publishing as an Artifact.
import { readFileSync, writeFileSync } from 'node:fs';
const src = f => readFileSync(new URL(`./src/${f}`, import.meta.url), 'utf8');
const head = `<title>Eduwit B2C CRM Prototype</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Geist:wght@400..700&family=Geist+Mono:wght@400..600&display=swap">
<style>${src('styles.css')}</style>`;
const body = `<div id="app"></div>
<script>${['data.js', 'core.js', 'sales.js', 'workspace.js'].map(src).join('\n')}
render();</script>`;
writeFileSync(new URL('./prototype.html', import.meta.url), `<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n${head}\n</head>\n<body>\n${body}\n</body>\n</html>\n`);
const i = process.argv.indexOf('--fragment');
if (i > 0) writeFileSync(process.argv[i + 1], `${head}\n${body}\n`);
console.log('built');
