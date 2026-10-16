Pod::Spec.new do |s|
  s.name = 'hnuhole_auth_passkey'
  s.version = '0.1.0'
  s.summary = 'Native discoverable Passkey bridge.'
  s.description = 'Bounded server-driven AuthenticationServices credential operations.'
  s.homepage = 'https://github.com/zhubaozhenshuai666-lang/HnuHole'
  s.license = { :type => 'Proprietary' }
  s.author = { 'Hnuhole' => 'hnuhole@example.invalid' }
  s.source = { :path => '.' }
  s.source_files = 'hnuhole_auth_passkey/Sources/hnuhole_auth_passkey/**/*.swift'
  s.dependency 'Flutter'
  s.frameworks = 'AuthenticationServices'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
  s.test_spec 'CodecTests' do |t|
    t.source_files = 'hnuhole_auth_passkey/Tests/HnuholePasskeyCodecTests/*.swift'
  end
end
