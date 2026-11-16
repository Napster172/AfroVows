import json,os,re
here=os.path.dirname(os.path.abspath(__file__));pub=os.path.join(here,'..','..','public','i18n')
master=json.load(open(os.path.join(here,'master.json')))
for lang in ['es','de','fr','it','ar']:
    d={}
    for ln in open(os.path.join(here,lang+'.txt'),encoding='utf-8').read().splitlines():
        if not ln.strip():continue
        i,t=ln.split('|',1);d[master[int(i)]]=t
    open(os.path.join(pub,lang+'.js'),'w',encoding='utf-8').write("window.AV_I18N=window.AV_I18N||{};window.AV_I18N."+lang+"="+json.dumps(d,ensure_ascii=False,indent=0)+";\n")
    print(lang,len(d))
