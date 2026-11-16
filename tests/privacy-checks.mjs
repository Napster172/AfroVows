// Privacy checks against a local Supabase (npx supabase start, then: node tests/privacy-checks.mjs).
// Uses the local stack's default publishable key, not the live project.
import {createClient} from '@supabase/supabase-js';
const URL='http://127.0.0.1:54321',KEY='sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';
const mk=()=>createClient(URL,KEY,{auth:{persistSession:false}});
const ok=(c,m)=>console.log((c?'PASS ':'FAIL ')+m);
const su=async(email,meta)=>{const c=mk();const {data,error}=await c.auth.signUp({email,password:'password123',options:{data:meta}});if(error)throw error;return c};
const a=await su('a@x.gh',{role:'couple',p1:'Ama',p2:'Kofi'});
const {data:pa}=await a.from('profiles').select('*').single();
const {data:w,error:we}=await a.from('weddings').insert({code:'AMAKOFI11',data:{wedding:{p1:'Ama'},guests:[{id:'g1',name:'Efua Asante',phone:'0551000003',events:'eng,wed'}],team:[{id:'t1',name:'Ama',role:'Bride',email:'a@x.gh',status:'joined',owner:true},{id:'t2',name:'Kofi',role:'Groom',email:'',status:'invited',code:'AV-TEST11'}]}}).select().single();
ok(!we&&w,'couple creates wedding '+(we?.message||''));
const {error:we2}=await a.from('weddings').insert({code:'AMAKOFI12',data:{}});ok(!!we2,'couple cannot create a second wedding');
const b=await su('b@x.gh',{role:'couple'});
const {data:bw}=await b.from('weddings').select('*');ok(bw.length===0,'other couple cannot read the wedding');
const {data:bu}=await b.from('weddings').update({data:{}}).eq('id',w.id).select();ok(!bu||bu.length===0,'other couple cannot change the wedding');
const anon=mk();
const {data:aw}=await anon.from('weddings').select('*');ok(aw.length===0,'anon cannot read weddings');
const {data:gw}=await anon.rpc('guest_wedding',{wcode:'amakofi11'});ok(gw&&gw.wedding&&!gw.guests&&!gw.team,'guest sees only public wedding parts');
const {data:gf}=await anon.rpc('guest_find',{wcode:'AMAKOFI11',q:'0551 000 003'});ok(gf&&gf.name==='Efua Asante'&&!gf.phone,'guest finds own invite by phone, no phone leaked');
const {data:gf2}=await anon.rpc('guest_find',{wcode:'AMAKOFI11',q:'Efua'});ok(!gf2,'partial name does not match');
await anon.rpc('guest_rsvp',{wcode:'AMAKOFI11',guest_id:'g1',answers:{eng:'yes',wed:'maybe',x:'<b>'},note:'See you'});
const {data:w2}=await a.from('weddings').select('data').single();ok(JSON.stringify(w2.data.guests[0].rsvp)==='{"eng":"yes"}'&&w2.data.guests[0].note==='See you','rsvp saved and cleaned');
const {data:badp}=await anon.rpc('guest_add_photo',{wcode:'AMAKOFI11',by_name:'x',url:'https://evil.com/a.jpg'});ok(badp===false,'guest photo must be our storage URL');
const {data:iv}=await anon.rpc('invite_check',{invite:'av-test11',first_name:'Kofi',last_name:'Mensah'});ok(iv==='ok','invite code valid for the invited first name');
const {data:ivn}=await anon.rpc('invite_check',{invite:'AV-TEST11',first_name:'Kwame',last_name:'Mensah'});ok(ivn==='name','wrong name is refused');
const {data:rq}=await b.rpc('request_join',{invite:'AV-TEST11',first_name:'Kofi',last_name:'Mensah'});ok(rq==='requested','partner asks to join');
const {data:bw1}=await b.from('weddings').select('id');ok(bw1.length===0,'asking to join gives no access before approval');
const {data:aw1}=await a.from('weddings').select('data').single();
await a.from('weddings').update({data:{...aw1.data,team:aw1.data.team.map(x=>x.status==='requested'?{...x,status:'joined'}:x)}}).eq('id',w.id);
const {data:bw2}=await b.from('weddings').select('data').single();ok(bw2&&bw2.data.team[1].status==='joined'&&bw2.data.team[1].email==='b@x.gh','approved partner can read and is marked joined');
// remove partner from team -> loses access
const t=bw2.data.team.filter(x=>x.role!=='Groom');await a.from('weddings').update({data:{...bw2.data,team:t}}).eq('id',w.id);
const {data:bw3}=await b.from('weddings').select('id');ok(bw3.length===0,'removed partner loses access');
// admin escalation
const h=await su('h@x.gh',{role:'admin'});const {data:ph}=await h.from('profiles').select('role').single();ok(ph.role==='couple','cannot sign up as admin');
await h.from('profiles').update({role:'admin'}).eq('email','h@x.gh');const {data:ph2}=await h.from('profiles').select('role').single();ok(ph2.role==='couple','cannot promote self');
// vendor
const v=await su('v@x.gh',{role:'vendor',biz:'Snaps'});
const {error:le}=await v.from('listings').insert({id:'l1',status:'approved',plan:'featured',live:{name:'hack'},data:{name:'Snaps',reg:'RG123'}});ok(!le,'vendor inserts listing');
const {data:l1}=await v.from('listings').select('*').single();ok(l1.status==='draft'&&l1.plan==='basic'&&!l1.live,'vendor cannot self-approve or set plan');
const {data:pubs}=await anon.from('public_listings').select('*');ok(pubs.length===0,'unapproved listing not public');
const {data:al}=await anon.from('listings').select('*');ok(al.length===0,'anon cannot read listings table');
const {error:ce}=await a.from('listings').insert({id:'l2',data:{}});ok(!!ce,'couple cannot create listing');
// messages
const {error:me}=await anon.from('messages').insert({id:'m1',name:'Yaw',msg:'Hi'});ok(!me,'anon sends message '+(me?.message||''));
const {data:ms}=await anon.from('messages').select('*');ok(ms.length===0,'anon cannot read messages');
const {error:sc}=await a.from('site_content').upsert({key:'content',value:{x:1}});ok(!!sc,'couple cannot edit site');
// reviews
const {error:re}=await a.from('reviews').insert({id:'r1',vendor_id:'v1',rating:5,text:'Great'});ok(!re,'couple reviews');
const {error:re2}=await v.from('reviews').insert({id:'r2',vendor_id:'v1',rating:1,text:'x'});ok(!!re2,'vendor cannot review');
// storage
const blob=new Blob(['%PDF-1.4'],{type:'application/pdf'});
const {error:d1}=await a.storage.from('docs').upload(w.id+'/x.pdf',blob);ok(!d1,'couple uploads doc '+(d1?.message||''));
const {error:d2}=await b.storage.from('docs').download(w.id+'/x.pdf');ok(!!d2,'removed partner cannot read doc');
const {error:d3}=await anon.storage.from('docs').download(w.id+'/x.pdf');ok(!!d3,'anon cannot read doc');
const img=new Blob([new Uint8Array([255,216,255])],{type:'image/jpeg'});
const {error:m1}=await a.storage.from('media').upload('u/'+pa.id+'/a.jpg',img);ok(!m1,'user uploads own media');
const {error:m2}=await a.storage.from('media').upload('u/someoneelse/a.jpg',img);ok(!!m2,'cannot upload into another user folder');
