source 'https://github.com/CocoaPods/Specs.git'

platform :ios, '9.0'

use_frameworks!

def fabric
    pod 'Fabric'
    pod 'Crashlytics'
end

def library
    pod 'KissXML'
    pod 'KissXML/libxml_module'
    pod 'ICSMainFramework', :path => "./Library/ICSMainFramework/"
    pod 'MMWormhole', '~> 2.0.0'
    pod 'KeychainAccess'
end


def tunnel
    pod 'MMWormhole', '~> 2.0.0'
end

def socket
    pod 'CocoaAsyncSocket', '~> 7.4.3'
end

def model
platform :ios, '9.0'
   pod 'RealmSwift'
end

target "Potatso" do
    pod 'Aspects', :path => "./Library/Aspects/"
    #pod 'Cartography'
    pod 'Cartography', :git => 'https://github.com/mluisbrown/Cartography.git', :branch => 'swift3'
    pod 'AsyncSwift'
    pod 'SwiftColor', '~> 0.3.7'
    pod 'Appirater'
    pod 'MBProgressHUD'
pod 'Eureka', '~> 2.0.0-beta.1'
    pod 'CallbackURLKit'
    pod 'ICDMaterialActivityIndicatorView', '~> 0.1.0'
    pod 'Reveal-iOS-SDK', '~> 1.6.2', :configurations => ['Debug']
    pod 'ICSPullToRefresh', '~> 0.4'
    pod 'ISO8601DateFormatter', '~> 0.8'
    pod 'Alamofire'
    pod 'ObjectMapper'
    pod 'CocoaLumberjack/Swift', '~> 3.0'
    pod 'Helpshift', '5.6.1'
    pod 'PSOperations', '~> 3.0'
#    pod 'LogglyLogger-CocoaLumberjack', '~> 2.0'
    tunnel
    library
    fabric
    socket
    model
end

target "PacketTunnel" do
    tunnel
    socket
end

target "PacketProcessor" do
    socket
end

target "TodayWidget" do
    #pod 'Cartography'
    pod 'Cartography', :git => 'https://github.com/mluisbrown/Cartography.git', :branch => 'swift3'
    pod 'SwiftColor'
    library
    socket
    model
end

target "PotatsoLibrary" do
    library
    model
end

target "PotatsoModel" do
    model
end

#target "PotatsoLibraryTests" do
#    library
#end

post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['ENABLE_BITCODE'] = 'NO'
            config.build_settings['SWIFT_VERSION'] = '3.0'
            if target.name == "HelpShift"
                config.build_settings["OTHER_LDFLAGS"] = '$(inherited) "-ObjC"'
            end
        end
    end
end
