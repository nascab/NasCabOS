Pod::Spec.new do |s|
  s.name             = 'ass'
  s.version          = '0.1.0'
  s.summary          = 'libass framework'
  s.description      = 'libass framework for FVP'
  s.homepage         = 'https://github.com/libass/libass'
  s.license          = { :type => 'MIT' }
  s.author           = { 'libass' => 'libass' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '11.0'
  s.vendored_frameworks = 'ass.framework'
end
