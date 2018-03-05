Pod::Spec.new do |s|

  s.name         = "YAMediaKit"
  s.version      = "0.0.4"
  s.summary      = "YAMediaKit"

  s.description  = "YAMediaKit"

  s.homepage     = "https://github.com/onesmash/YAMediaKit"


  s.license      = { :type => "MIT", :file => "LICENSE" }

  s.author             = { "xuhui" => "good122000@qq.com" }

  s.platform     = :ios, "8.0"

  s.source       = { :git => "https://github.com/onesmash/YAMediaKit.git", :tag => "#{s.version}" }

  s.source_files  = ["YAMediaKit.h", "AVKit/**/*.{h,m,mm}"]

  s.public_header_files = ["YAMediaKit.h", "AVKit/AVPlayerItem+YA.h"]

  s.requires_arc = true

  s.dependency "YAKit"

end
