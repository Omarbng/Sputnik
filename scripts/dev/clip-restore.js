ObjC.import('AppKit'); ObjC.import('Foundation');
function run(argv) {
  var json = $.NSString.stringWithContentsOfFileEncodingError(argv[0], 4, null).js, recs = JSON.parse(json);
  var pb = $.NSPasteboard.generalPasteboard, objs = [];
  pb.clearContents;
  recs.forEach(function (rec) {
    var item = $.NSPasteboardItem.alloc.init;
    Object.keys(rec).forEach(function (t) { item.setDataForType($.NSData.alloc.initWithBase64EncodedStringOptions(rec[t], 0), t); });
    objs.push(item);
  });
  return pb.writeObjects($(objs)) ? "restored " + recs.length : "restore failed";
}
