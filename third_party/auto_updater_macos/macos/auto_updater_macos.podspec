Pod::Spec.new do |s|
  s.name             = 'auto_updater_macos'
  s.version          = '1.0.0'
  s.summary          = 'macOS implementation of auto_updater.'
  s.description      = 'Sparkle-backed macOS automatic updates for Leeef Reader.'
  s.homepage         = 'https://github.com/leanflutter/auto_updater'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'LiJianying' => 'lijy91@foxmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.dependency 'Sparkle'
  s.platform         = :osx, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
