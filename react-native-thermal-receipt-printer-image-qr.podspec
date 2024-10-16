require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name         = 'rn-thermal-receipt-printer'
  s.version      = package['version']
  s.summary      = package['description']
  s.license      = package['license']

  s.authors      = package['author']
  s.homepage     = package['homepage']
  s.platform     = :ios, "9.0"

  s.source       = { :git => "https://github.com/IshmamR/promethewz-rn-thermal-receipt-printer", :tag => "v#{s.version}" }
  s.source_files  = "ios/**/*.{h,m}"
  s.requires_arc = true
  s.ios.vendored_libraries = "ios/PrinterSDK/libPrinterSDK.a"
  s.xcconfig = { 'HEADER_SEARCH_PATHS' => '"${PROJECT_DIR}/PrinterSDK"/**' }

  s.dependency 'React'
end
