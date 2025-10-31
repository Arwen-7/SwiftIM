Pod::Spec.new do |s|
  s.name             = 'SwiftIM'
  s.version          = '1.0.0'
  s.summary          = 'Enterprise-grade IM SDK for iOS, built with Swift'
  
  s.description      = <<-DESC
    SwiftIM is a native iOS instant messaging SDK that provides:
    • Dual transport layer (WebSocket + TCP)
    • Message reliability with ACK + Retry + Queue
    • Rich media messages (Image, Audio, Video, File)
    • Message loss detection and recovery
    • SQLite + WAL for high performance
    • Protobuf serialization
    • Well documented (19,500+ lines)
                       DESC

  s.homepage         = 'https://github.com/Arwen-7/SwiftIM'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'SwiftIM Team' => 'support@swiftim.io' }
  s.source           = { :git => 'https://github.com/Arwen-7/SwiftIM.git', :tag => s.version.to_s }
  
  s.ios.deployment_target = '13.0'
  s.swift_version = '5.9'
  
  s.source_files = 'Sources/IMSDK/**/*.swift'
  s.resources = 'Sources/IMSDK/**/*.proto'
  
  s.frameworks = 'Foundation', 'UIKit', 'Network'
  
  s.dependency 'Alamofire', '~> 5.8'
  s.dependency 'Starscream', '~> 4.0'
  s.dependency 'CryptoSwift', '~> 1.8'
  s.dependency 'SwiftProtobuf', '~> 1.25'
  
  s.pod_target_xcconfig = {
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => 'SWIFTIM_COCOAPODS'
  }
end

