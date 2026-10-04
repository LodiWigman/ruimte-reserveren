// Read-only source inventory. Uses the parser already bundled with the test runner.
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {babelParse,traverse}=require('../node_modules/playwright/lib/transform/babelBundle.js');
const html=await readFile('index.html','utf8'),match=html.match(/<script>\s*([\s\S]*?)<\/script>/);
const ast=babelParse(match[1],'index.js',true),strings=[];
traverse(ast,{StringLiteral(path){strings.push({value:path.node.value,start:path.node.start,end:path.node.end,parent:path.parent.type,key:path.key,callee:path.parent.callee?.name});}});
if(process.argv.includes('--tokens'))console.log(JSON.stringify({script:match[1],offset:html.indexOf(match[1]),strings}));
else console.log([...new Set(strings.map(s=>s.value).filter(s=>/\s|[A-Z][a-z]/.test(s)&&!s.includes('<')&&!s.includes('>')&&!s.includes('https:')))].sort().join('\n'));
