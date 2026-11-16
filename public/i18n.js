/* AfroVows language switcher.
   The app renders English; this file swaps on-screen text for the chosen language.
   Dictionaries live in i18n/<lang>.js and are keyed by the English text, with numbers and
   dates replaced by {0}, {1}... so "4 of 20 to-dos" matches "{0} of {1} to-dos".
   Text with no match stays in English (e.g. names, notes and other things people type). */
(function(){
  var LANGS={en:"English",es:"Español",de:"Deutsch",fr:"Français",it:"Italiano",ar:"العربية"};
  var LOCALE={en:"en-GB",es:"es-ES",de:"de-DE",fr:"fr-FR",it:"it-IT",ar:"ar-u-nu-latn"};
  var W=window.AV_I18N=window.AV_I18N||{};
  var lang="en";try{lang=localStorage.getItem("afrovows.lang")||"en"}catch(e){}
  if(!LANGS[lang]&&lang!=="xx")lang="en";
  var MON="Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|June?|July?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?";
  var DATE="(?:(?:Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)day,?\\s)?\\d{1,2}\\s(?:"+MON+")\\b(?:\\s\\d{4})?";
  var TOK=new RegExp(DATE+"|\\d[\\d,.]*\\d|\\d","g");
  var SKIP={SCRIPT:1,STYLE:1,TEXTAREA:1,CODE:1,NOSCRIPT:1};
  var ATTRS=["placeholder","aria-label","title"];
  var miss=window.__avMiss=window.__avMiss||new Set();

  function fmtDate(m){
    var wk=/day,?\s/.test(m),rest=m.replace(/^\w+day,?\s/,""),yr=/\d{4}$/.test(rest);
    var d=new Date(Date.parse(rest+(yr?"":" "+new Date().getFullYear())));
    if(isNaN(d))return m;
    var mon=(rest.match(/[A-Za-z]+/)||[""])[0];
    var o={day:"numeric",month:mon.length>3||mon==="May"?"long":"short"};if(wk)o.weekday="long";if(yr)o.year="numeric";
    try{return new Intl.DateTimeFormat(LOCALE[lang]||"en-GB",o).format(d)}catch(e){return m}
  }
  function tr(s){
    if(lang==="en"||!/[A-Za-z]/.test(s))return s;
    var lead=s.match(/^\s*/)[0],trail=s.match(/\s*$/)[0],core=s.trim().replace(/\s+/g," ");
    if(!core)return s;
    var vals=[],key=core.replace(TOK,function(m){vals.push(m);return "{"+(vals.length-1)+"}"});
    if(key==="{0}"&&/[A-Za-z]/.test(vals[0]))return lead+fmtDate(vals[0])+trail;
    if(!/[A-Za-z]/.test(key.replace(/\{\d+\}/g,"")))return s;
    var D=W[lang];
    if(lang==="xx"){miss.add(key);return s}
    var t=D&&(D[key]||D[core]);
    if(!t)return s;
    if(D[key]){t=t.replace(/\{(\d+)\}/g,function(_,i){var v=vals[+i];return v==null?"":/[A-Za-z]/.test(v)?fmtDate(v):v})}
    return lead+t+trail;
  }
  function skipEl(el){
    for(var e=el;e&&e!==document;e=e.parentNode){
      if(e.nodeType!==1)continue;
      if(SKIP[e.tagName]||e.getAttribute("translate")==="no"||e.isContentEditable)return true;
      if(e.hasAttribute&&e.hasAttribute("data-edit")&&document.body.classList.contains("editing"))return true;
    }
    return false;
  }
  function doText(n){
    if(n.__tr===undefined||n.nodeValue!==n.__tr)n.__en=n.nodeValue;
    if(skipEl(n.parentNode)){n.__tr=n.__en;return}
    var out=tr(n.__en);n.__tr=out;if(n.nodeValue!==out)n.nodeValue=out;
    var p=n.parentNode;
    if(lang==="ar"&&p&&p.childNodes.length===1&&/^\s*\+?\d[\d\s()-]{6,}\s*$/.test(out)&&!p.hasAttribute("dir"))p.setAttribute("dir","ltr");
  }
  function doEl(el){
    if(el.tagName==="OPTION"&&!el.hasAttribute("value"))el.setAttribute("value",el.__enOpt||(el.__enOpt=el.textContent));
    if(skipEl(el))return;
    var A=el.__enA||(el.__enA={}),T=el.__trA||(el.__trA={});
    for(var i=0;i<ATTRS.length;i++){var a=ATTRS[i];if(!el.hasAttribute(a))continue;var v=el.getAttribute(a);
      if(T[a]===undefined||v!==T[a])A[a]=v;var out=tr(A[a]);T[a]=out;if(v!==out)el.setAttribute(a,out)}
  }
  function walk(root){
    if(!root)return;
    if(root.nodeType===3){doText(root);return}
    if(root.nodeType!==1||SKIP[root.tagName])return;
    doEl(root);
    var tw=document.createTreeWalker(root,5,{acceptNode:function(n){return n.nodeType===1&&SKIP[n.tagName]?2:1}}),n;
    var els=[],txt=[];while((n=tw.nextNode()))(n.nodeType===1?els:txt).push(n);
    els.forEach(doEl);txt.forEach(doText);
  }
  function applyDoc(){
    var h=document.documentElement;h.lang=lang==="xx"?"en":lang;h.dir=lang==="ar"?"rtl":"ltr";
    if(document.body)walk(document.body);
    var s=document.getElementById("langsel");if(s&&s.value!==lang)s.value=lang;
  }
  function load(l,cb){
    if(l==="en"||l==="xx"||W[l])return cb();
    var sc=document.createElement("script");sc.src="i18n/"+l+".js";sc.onload=cb;sc.onerror=cb;document.head.appendChild(sc);
  }
  function set(l){
    if(!LANGS[l]&&l!=="xx")l="en";
    try{localStorage.setItem("afrovows.lang",l)}catch(e){}
    load(l,function(){lang=l;if(l==="xx")W.xx=W.xx||{};applyDoc()});
  }
  window.AVI18N={set:set,tr:tr,get lang(){return lang},LANGS:LANGS};
  document.addEventListener("change",function(e){if(e.target&&e.target.id==="langsel")set(e.target.value)});
  function start(){
    var sel=document.getElementById("langsel");
    if(sel&&!sel.options.length){for(var k in LANGS){var o=document.createElement("option");o.value=k;o.textContent=LANGS[k];sel.appendChild(o)}}
    new MutationObserver(function(ms){
      if(lang==="en")return;
      for(var i=0;i<ms.length;i++){var m=ms[i];
        if(m.type==="childList")for(var j=0;j<m.addedNodes.length;j++)walk(m.addedNodes[j]);
        else if(m.type==="characterData"){if(m.target.nodeValue!==m.target.__tr)doText(m.target)}
        else if(m.type==="attributes")doEl(m.target);
      }
    }).observe(document.body,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:ATTRS});
    set(lang);
  }
  if(document.body)start();else document.addEventListener("DOMContentLoaded",start);
})();
