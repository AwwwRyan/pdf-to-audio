/// Turns a PDF's file name into a readable title:
/// "AWS_DevOps_Interview_Study_Guide.pdf" → "AWS DevOps Interview Study Guide".
/// Hyphens are kept ("SpotCare-style"); URL escapes from browser downloads
/// are decoded.
String titleFromFileName(String fileName) {
  var name = fileName.trim();
  final dot = name.lastIndexOf('.');
  if (dot > 0 && name.substring(dot).toLowerCase() == '.pdf') {
    name = name.substring(0, dot);
  }
  try {
    name = Uri.decodeComponent(name);
  } on ArgumentError {
    // Not URL-encoded after all (e.g. a literal "%"); keep as is.
  }
  name = name.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return name.isEmpty ? 'Untitled' : name;
}
