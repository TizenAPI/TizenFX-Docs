'use strict';

const fs = require('fs');
// Lunr 라이브러리 로드
const lunr = require('./_site/styles/lunr.min.js');

// 대용량 JSON 스트리밍 처리를 위한 라이브러리
const { chain } = require('stream-json/Parser');
const { streamObject } = require('stream-json/streamers/StreamObject');

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

    console.log('Building Indexes from ' + kSearchDataFile + ' (Streaming) ...');
    // 메모리를 아끼기 위해 로딩과 빌드를 동시에 수행합니다.
    const index = await buildIndexStreaming();

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

function buildIndexStreaming() {
  return new Promise((resolve, reject) => {
    // 1. Lunr Builder 수동 생성 (기존 lunr(function(){...}) 방식은 동기식이라 스트림에 부적합)
    const builder = new lunr.Builder();

    // 2. 파이프라인 설정 (기존 로직 그대로 이식)
    builder.pipeline.remove(lunr.stopWordFilter);
    builder.ref('href');
    builder.field('title', { boost: 50 });
    builder.field('keywords', { boost: 20 });

    // StopWord 필터 설정
    if (stopWords && stopWords.length > 0) {
      let docfxStopWordFilter = lunr.generateStopWordFilter(stopWords);
      lunr.Pipeline.registerFunction(docfxStopWordFilter, 'docfxStopWordFilter');
      builder.pipeline.add(docfxStopWordFilter);
      builder.searchPipeline.add(docfxStopWordFilter);
    }

    // 3. 파일 스트림 생성 및 파이프라인 연결
    // docfx의 index.json은 보통 {"uid": {data}, ...} 형태의 Object이므로 streamObject 사용
    const pipeline = fs.createReadStream(kSearchDataFile)
      .pipe(chain([
        streamObject(), // JSON 객체의 키-값 쌍을 하나씩 스트리밍
      ]));

    let count = 0;

    // 4. 데이터가 한 건씩 들어올 때마다 Lunr에 추가
    pipeline.on('data', (data) => {
      // data.key는 문서의 UID/URL, data.value는 문서 내용 객체
      const doc = data.value;
      if (doc) {
        builder.add(doc);
        count++;
        // 진행 상황 로그 (선택 사항)
        if (count % 10000 === 0) {
          console.log(`Indexed ${count} documents...`);
          // Node.js 가비지 컬렉션 유도 (옵션: 실행시 node --expose-gc 필요)
          if (global.gc) global.gc();
        }
      }
    });

    pipeline.on('end', () => {
      console.log(`Total ${count} documents indexed.`);
      // 5. 인덱스 빌드 완료
      resolve(builder.build());
    });

    pipeline.on('error', (err) => {
      reject(err);
    });
  });
}

function saveIndex(lunrIndex) {
  fs.writeFileSync(kPrebuiltFile, JSON.stringify(lunrIndex));
}