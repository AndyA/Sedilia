const data = require("../../../tmp/mcc.json");

const rows = [];
function emit(key, value) {
  rows.push({ key, value });
}

const viewMap = function (doc) {
  if (!doc.mcc_cdc) {
    return;
  }
  const source = doc.contentType ? doc.contentType.source : "tagging";
  emit(
    [
      new Date(doc.mcc_cdc.sequence * 1000).toISOString(),
      doc.mcc_cdc.sequence,
      doc.mcc_cdc.update_type,
      doc.mcc_cdc.object_type,
      source,
    ],
    1,
  );
};

const TOTAL = 12339702;
const scale = Math.ceil(TOTAL / data.length);

console.log(`Processing ${data.length} rows ${scale} times each`);
const start = Date.now();
for (let i = 0; i < scale; i++) {
  for (const row of data) {
    viewMap(row);
  }
}
const duration = Date.now() - start;
console.log(`Emitted ${rows.length} rows in ${duration}ms`);
