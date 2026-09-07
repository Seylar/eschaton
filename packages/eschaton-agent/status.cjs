'use strict';
const {execFile}=require('node:child_process');
const {promisify}=require('node:util');
const execute=promisify(execFile);
// Fixed, read-only commands. Unit descriptions and package names remain data.
async function collect(run=execute) {
    const sources=[
        ['systemServices','/usr/bin/systemctl',['--failed','--no-legend','--plain','--no-pager']],
        ['userServices','/usr/bin/systemctl',['--user','--failed','--no-legend','--plain','--no-pager']],
        ['disk','/usr/bin/df',['-h','/']],
        ['packages','/usr/bin/pacman',['-Q']]
    ];
    const values=await Promise.all(sources.map(async([name,program,args])=>{
        try {const {stdout}=await run(program,args,{timeout:5000,maxBuffer:524288});
            return [name,{available:true,text:stdout.slice(0,10000),truncated:stdout.length>10000}];}
        catch(_){return [name,{available:false,error:'Lecture indisponible ou délai dépassé.'}];}
    }));
    return {classification:'UNTRUSTED_SYSTEM_DATA',observedAt:new Date().toISOString(),sources:Object.fromEntries(values)};
}
module.exports={collect};
