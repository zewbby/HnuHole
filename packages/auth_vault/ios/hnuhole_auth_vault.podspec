Pod::Spec.new do |s|
  s.name = 'hnuhole_auth_vault'
  s.version = '0.1.0'
  s.summary = 'Device bound durable authentication storage.'
  s.description = 'A serialized, non-synchronizing Keychain authentication record.'
  s.homepage = 'https://github.com/zhubaozhenshuai666-lang/HnuHole'
  s.license = { :type => 'Proprietary' }
  s.author = { 'Hnuhole' => 'hnuhole@example.invalid' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
end
