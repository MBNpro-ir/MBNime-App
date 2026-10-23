// Serve the separate production-player probe on loopback with /qa-config
// containing the test title ID. Source metadata and media are fetched directly.
const {chromium,webkit,devices}=require(process.env.MBN_PLAYWRIGHT_PATH);
const assert=require('node:assert/strict');
(async()=>{
 for(const engine of (process.env.MBN_BROWSER_ENGINE?[process.env.MBN_BROWSER_ENGINE]:['chrome','webkit'])) {
  const proxy=process.env.HTTPS_PROXY?{server:process.env.HTTPS_PROXY,bypass:'127.0.0.1,localhost'}:undefined;
  const browser=engine==='chrome'?await chromium.launch({channel:'chrome',headless:true,proxy}):await webkit.launch({executablePath:process.env.MBN_WEBKIT_EXECUTABLE,headless:true,proxy});
  try {
   const context=await browser.newContext(engine==='webkit'?devices['iPhone 11 Pro']:{viewport:{width:1280,height:720}});
   if(engine==='webkit') await context.addInitScript(()=>Object.defineProperty(navigator,'standalone',{get:()=>true}));
   const page=await context.newPage();
   page.on('pageerror',e=>console.log(engine,'page error',e.message.slice(0,220)));
   page.on('requestfailed',r=>console.log(engine,'request failed',new URL(r.url()).host,r.failure()?.errorText));
   page.on('console',m=>{if(m.type()==='error') console.log(engine,'console error',m.text().slice(0,220));});
   await page.addInitScript(()=>{
    window.qaVideos=()=>{
      const result=[];
      function walk(root){result.push(...root.querySelectorAll('video'));for(const e of root.querySelectorAll('*'))if(e.shadowRoot)walk(e.shadowRoot);}
      walk(document);return result;
    };
    window.qaSelectedVideo=()=>{
      const target=JSON.parse(mbnSourceState()).media;
      return target&&qaVideos().find(v=>v.currentSrc===new URL(target).href);
    };
   });
   await page.goto('http://127.0.0.1:8773/');
   try {await page.waitForFunction(()=>window.mbnSourceLoad,null,{timeout:60000});}
   catch(error) {
    console.log(engine,'startup diagnostics',await page.evaluate(()=>({stage:window.mbnProbeStage,scriptCount:document.scripts.length,ready:document.readyState,flutterViews:document.querySelectorAll('flutter-view').length})));
    throw error;
   }
   console.log(engine,'probe ready');
   await page.evaluate(async()=>{const q=await(await fetch('/qa-config')).json();mbnSourceLoad(q.title);});
   await page.waitForFunction(()=>JSON.parse(mbnSourceState()).state!=='idle',null,{timeout:90000});
   assert.equal(await page.evaluate(()=>JSON.parse(mbnSourceState()).state),'loaded','source metadata must load');
   assert((await page.evaluate(()=>JSON.parse(mbnSourceState()).episodes))>=3);
   console.log(engine,'source loaded');
   for(const quality of ['480p','720p','1080p']) {
    await page.evaluate(q=>mbnSourceOpen(q),quality);
    try {await page.waitForFunction(()=>qaSelectedVideo()?.readyState>=1,null,{timeout:60000});}
    catch(error) {
      console.log(engine,quality,'video diagnostics',await page.evaluate(()=>qaVideos().map(v=>({ready:v.readyState,network:v.networkState,error:v.error?.code,host:v.currentSrc?new URL(v.currentSrc).host:''}))));
      throw error;
    }
    await page.evaluate(async()=>{const v=qaSelectedVideo();v.muted=true;await v.play();});
    await page.waitForFunction(()=>qaSelectedVideo()?.currentTime>2,null,{timeout:30000});
    let state=await page.evaluate(()=>{const v=qaSelectedVideo();return {duration:v.duration,width:v.videoWidth,height:v.videoHeight,error:v.error?.code||0};});
    assert(state.duration>1100&&state.duration<1300);
    assert.equal(state.error,0);
    await page.evaluate(()=>{const v=qaSelectedVideo();v.currentTime=300;});
    await page.waitForFunction(()=>{const v=qaSelectedVideo();return v&&v.currentTime>302&&!v.seeking&&!v.paused;},null,{timeout:30000});
    await page.evaluate(()=>qaSelectedVideo().pause());
    await page.waitForTimeout(500);
    await page.evaluate(()=>qaSelectedVideo().play());
    await page.waitForFunction(()=>qaSelectedVideo()?.currentTime>304,null,{timeout:15000});
    console.log(JSON.stringify({engine,quality,...state,play:true,seek:true,pauseResume:true}));
   }
   await context.close();
  } finally {await browser.close();}
 }
})().catch(error=>{console.error(error.message);process.exitCode=1;});
