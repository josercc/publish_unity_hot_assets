/// Jenkins workspace 目录或文件条目。
class JenkinsWorkspaceEntry {
  final String name;
  final String href;
  final bool isDirectory;
  final String? sizeText;

  const JenkinsWorkspaceEntry({
    required this.name,
    required this.href,
    required this.isDirectory,
    this.sizeText,
  });

  bool get isApk =>
      !isDirectory && name.toLowerCase().endsWith('.apk');
}
