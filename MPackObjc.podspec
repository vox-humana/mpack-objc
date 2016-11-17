Pod::Spec.new do |s|
  s.name             = "MPackObjc"
  s.version          = "0.0.1"
  s.summary          = "MPack Objective-C wrapper."
  s.homepage         = "https://github.com/vox-humana/mpack-objc"
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { "Arthur Semenyutin" => "semenyutin@gmail.com" }
  s.source           = { :git => "https://github.com/vox-humana/mpack-objc.git", :tag => s.version }

  s.platform     = :ios, '7.0'
  s.requires_arc = true

  s.source_files = "*.{h,m,c}"
  s.public_header_files = "MPackObjc.h"
end
