'use strict';

const fs = require('fs');
// Lunr 라이브러리 로드
const lunr = require('lunr');

// 대용량 JSON 스트리밍 처리를 위한 라이브러리
const JSONStream = require('JSONStream');

const kStopWordFile = './_site/search-stopwords.json';
const kSearchDataFile = './_site/index.json';
const kPrebuiltFile = './_site/index-prebuilt.json';

let stopWords = null;

// 메인 실행 함수 (Async 처리)
(async () => {
  try {
    lunr.tokenizer.separator = /[\s\-\.\(\)]+/;

    console.log('Loading ' + kStopWordFile + ' ...');
    loadStopWords();

    console.log('Building Indexes from multiple index-*.json files (Streaming) ...');
    // 메모리를 아끼기 위해 로딩과 빌드를 동시에 수행합니다.
    const index = await buildIndexFromAllFiles();

    console.log('Saving prebuilt indexes ... => ' + kPrebuiltFile);
    saveIndex(index);

    console.log('Done.');
  } catch (err) {
    console.error('Error:', err);
    process.exit(1);
  }
})();

function loadStopWords() {
  if (fs.existsSync(kStopWordFile)) {
    let data = fs.readFileSync(kStopWordFile);
    stopWords = JSON.parse(data);
  } else {
    console.warn('Stopword file not found, skipping.');
    stopWords = [];
  }
}

async function buildIndexFromAllFiles() {
  const builder = new lunr.Builder();
  builder.pipeline.remove(lunr.stopWordFilter);
  builder.ref('href');
  builder.field('title', { boost: 50 });
  builder.field('keywords', { boost: 20 });

  if (stopWords && stopWords.length > 0) {
    let docfxStopWordFilter = lunr.generateStopWordFilter(stopWords);
    lunr.Pipeline.registerFunction(docfxStopWordFilter, 'docfxStopWordFilter');
    builder.pipeline.add(docfxStopWordFilter);
    builder.searchPipeline.add(docfxStopWordFilter);
  }

  // _site 폴더에서 index-*.json 파일을 모두 찾아 순차 처리
  const siteDir = './_site';
  const files = fs.readdirSync(siteDir)
    .filter(f => f.startsWith('index-') && f.endsWith('.json') && f !== 'index-prebuilt.json');

  if (files.length === 0) {
     const singleFile = './_site/index.json';
     if (fs.existsSync(singleFile)) files.push('index.json');
  }

  console.log(`Found ${files.length} index files to merge.`);

  for (const file of files) {
    const filePath = `${siteDir}/${file}`;
    console.log(`Processing ${file} ...`);
    await streamFileIntoBuilder(filePath, builder);
  }

  return builder.build();
}

function streamFileIntoBuilder(filePath, builder) {
  return new Promise((resolve, reject) => {
    const pipeline = fs.createReadStream(filePath)
      .pipe(JSONStream.parse('$*'));

    let count = 0;
    pipeline.on('data', (doc) => {
      if (doc) {
        builder.add(doc);
        count++;
        if (count % 10000 === 0) {
          if (global.gc) global.gc();
        }
      }
    });

    pipeline.on('end', () => {
      console.log(`Finished ${filePath}: ${count} documents added.`);
      resolve();
    });

    pipeline.on('error', (err) => {
      reject(err);
    });
  });
}

function saveIndex(lunrIndex) {
  fs.writeFileSync(kPrebuiltFile, JSON.stringify(lunrIndex));
}