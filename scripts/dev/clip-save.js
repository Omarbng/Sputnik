ObjC.import('AppKit'); ObjC.import('Foundation');
function run(argv) {
  var pb = $.NSPasteboard.generalPasteboard, items = pb.pasteboardItems, out = [];
  for (var i = 0; i < items.count; i++) {
    var it = items.objectAtIndex(i), types = it.types, rec = {};
    for (var j = 0; j < types.count; j++) {
      var t = types.objectAtIndex(j).js, d = it.dataForType(t);
      if (d && !d.isNil()) rec[t] = d.base64EncodedStringWithOptions(0).js;
    }
    out.push(rec);
  }
  $.NSString.alloc.initWithUTF8String(JSON.stringify(out)).writeToFileAtomicallyEncodingError(argv[0], true, 4, null);
  return out.length + " items";
}
