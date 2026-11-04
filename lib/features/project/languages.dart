import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

/// highlight.js language id for a file name, or null for plain text.
String? languageIdFor(String path) {
  final name = path.split('/').last.toLowerCase();
  if (name == 'dockerfile' || name == 'makefile') return 'bash';
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  return switch (name.substring(dot + 1)) {
    'dart' => 'dart',
    'ts' || 'tsx' || 'mts' || 'cts' => 'typescript',
    'js' || 'jsx' || 'mjs' || 'cjs' => 'javascript',
    'json' || 'jsonc' || 'lock' => 'json',
    'py' => 'python',
    'rs' => 'rust',
    'go' => 'go',
    'php' => 'php',
    'java' => 'java',
    'kt' || 'kts' => 'kotlin',
    'swift' => 'swift',
    'c' || 'h' => 'c',
    'cc' || 'cpp' || 'cxx' || 'hpp' || 'hh' => 'cpp',
    'rb' => 'ruby',
    'css' => 'css',
    'scss' || 'sass' => 'scss',
    'html' || 'htm' || 'xml' || 'svg' || 'vue' => 'xml',
    'yaml' || 'yml' => 'yaml',
    'toml' || 'ini' || 'cfg' || 'conf' => 'ini',
    'md' || 'markdown' => 'markdown',
    'sql' => 'sql',
    'sh' || 'bash' || 'zsh' => 'bash',
    _ => null,
  };
}

Mode? languageMode(String id) => switch (id) {
      'dart' => langDart,
      'typescript' => langTypescript,
      'javascript' => langJavascript,
      'json' => langJson,
      'python' => langPython,
      'rust' => langRust,
      'go' => langGo,
      'php' => langPhp,
      'java' => langJava,
      'kotlin' => langKotlin,
      'swift' => langSwift,
      'c' => langC,
      'cpp' => langCpp,
      'ruby' => langRuby,
      'css' => langCss,
      'scss' => langScss,
      'xml' => langXml,
      'yaml' => langYaml,
      'ini' => langIni,
      'markdown' => langMarkdown,
      'sql' => langSql,
      'bash' => langBash,
      _ => null,
    };
