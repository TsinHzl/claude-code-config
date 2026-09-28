const https = require('https');
const q = encodeURIComponent("大模型代码能力排行榜 2026");
https.get(`https://www.sogou.com/web?query=${q}`, (res) => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => {
    const matches = [...data.matchAll(/<h3 class="vr-title">.*?<a[^>]*>(.*?)<\/a>.*?<div class="star-wiki">(.*?)<\/div>/gs)];
    if(matches.length > 0) {
      matches.forEach(m => console.log(m[1].replace(/<[^>]+>/g, '')));
    } else {
      console.log("No rich results. Extracting plain titles:");
      const titles = [...data.matchAll(/<h3 class="[vp]r-title">.*?<a[^>]*>(.*?)<\/a>/g)];
      titles.slice(0,5).forEach(m => console.log(m[1].replace(/<[^>]+>/g, '')));
    }
  });
}).on('error', console.error);
