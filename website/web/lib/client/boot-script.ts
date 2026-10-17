/**
 * Runs inline in <head> before first paint (kept tiny; its sha256 is allowed by the CSP — see lib/server/csp.ts).
 * 1. Theme: localStorage "eduwit-theme" = "dark" | "light" | "system" (default from data-default-theme), resolved
 *    against prefers-color-scheme, written to <html data-theme>.
 * 2. Capability tier (spec 10.4, docs/ARCHITECTURE.md §8): <html data-tier="low|mid|high">.
 * Every storage access is wrapped: storage can throw in private mode or when blocked.
 */
export const BOOT_SCRIPT = `(function(){var d=document.documentElement;try{var p=null;try{p=localStorage.getItem("eduwit-theme")}catch(e){}var def=d.getAttribute("data-default-theme")||"dark";var m=p||def;if(m==="system"){m=matchMedia("(prefers-color-scheme: light)").matches?"light":"dark"}d.setAttribute("data-theme",m==="light"?"light":"dark");var n=navigator,c=n.connection||{},mem=n.deviceMemory||4,cpu=n.hardwareConcurrency||4,rm=matchMedia("(prefers-reduced-motion: reduce)").matches,gl=false;try{var cv=document.createElement("canvas");gl=!!(cv.getContext("webgl2")||cv.getContext("webgl"))}catch(e){}var t="high";if(rm||c.saveData||mem<=2||cpu<=4||!gl){t="low"}else if(mem<=4){t="mid"}d.setAttribute("data-tier",t);if(rm)d.setAttribute("data-motion","reduced")}catch(e){d.setAttribute("data-tier","low")}})();`;
