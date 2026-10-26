require "fileutils"
root = File.expand_path("..", __dir__)
files = Dir["#{root}/Sources/*.swift"].sort
objects=[]
def oid(n); "%024X" % n; end
files.each_with_index do |file,i|
 objects << "#{oid(100+i)} = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Sources/#{File.basename(file)}; sourceTree = SOURCE_ROOT; };"
 objects << "#{oid(200+i)} = {isa = PBXBuildFile; fileRef = #{oid(100+i)}; };"
end
objects << "#{oid(1)} = {isa = PBXProject; attributes = {LastUpgradeCheck = 1430; }; buildConfigurationList = #{oid(10)}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = es; knownRegions = (es,en,Base); mainGroup = #{oid(2)}; productRefGroup = #{oid(3)}; projectDirPath = \"\"; projectRoot = \"\"; targets = (#{oid(4)}); };"
objects << "#{oid(2)} = {isa = PBXGroup; children = (#{files.each_index.map{|i|oid(100+i)}.join(",")},#{oid(30)},#{oid(32)},#{oid(3)}); sourceTree = \"<group>\"; };"
objects << "#{oid(3)} = {isa = PBXGroup; children = (#{oid(5)}); name = Products; sourceTree = \"<group>\"; };"
objects << "#{oid(4)} = {isa = PBXNativeTarget; buildConfigurationList = #{oid(11)}; buildPhases = (#{oid(6)},#{oid(7)},#{oid(8)}); buildRules = (); dependencies = (); name = iPhoneRemote; productName = \"iPhone Remote\"; productReference = #{oid(5)}; productType = \"com.apple.product-type.application\"; };"
objects << "#{oid(5)} = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = \"iPhone Remote.app\"; sourceTree = BUILT_PRODUCTS_DIR; };"
objects << "#{oid(6)} = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (#{files.each_index.map{|i|oid(200+i)}.join(",")}); runOnlyForDeploymentPostprocessing = 0; };"
objects << "#{oid(7)} = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };"
objects << "#{oid(8)} = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (#{oid(31)},#{oid(33)}); runOnlyForDeploymentPostprocessing = 0; };"
objects << "#{oid(30)} = {isa = PBXFileReference; lastKnownFileType = folder; path = Resources/Web; sourceTree = SOURCE_ROOT; };"
objects << "#{oid(31)} = {isa = PBXBuildFile; fileRef = #{oid(30)}; };"
objects << "#{oid(32)} = {isa = PBXFileReference; lastKnownFileType = image.icns; path = Resources/AppIcon.icns; sourceTree = SOURCE_ROOT; };"
objects << "#{oid(33)} = {isa = PBXBuildFile; fileRef = #{oid(32)}; };"
[10,11].each do |n|
 objects << "#{oid(n)} = {isa = XCConfigurationList; buildConfigurations = (#{oid(n*10+500)},#{oid(n*10+501)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };"
 ["Debug","Release"].each_with_index do |name,i|
 settings = n == 10 ? "SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 13.0; CLANG_ENABLE_MODULES = YES;" : "PRODUCT_NAME = \"iPhone Remote\"; EXECUTABLE_NAME = iPhoneRemote; PRODUCT_BUNDLE_IDENTIFIER = local.iphoneremote.mac; INFOPLIST_FILE = Resources/Info.plist; SWIFT_VERSION = 5.0; CODE_SIGN_IDENTITY = \"-\"; CODE_SIGN_STYLE = Manual; ENABLE_APP_SANDBOX = NO; COMBINE_HIDPI_IMAGES = YES; SWIFT_OPTIMIZATION_LEVEL = #{i==0 ? "\"-Onone\"" : "\"-O\""};"
 objects << "#{oid(n*10+500+i)} = {isa = XCBuildConfiguration; buildSettings = {#{settings}}; name = #{name}; };"
 end
end
FileUtils.mkdir_p("#{root}/iPhoneRemote.xcodeproj/xcshareddata/xcschemes")
File.write("#{root}/iPhoneRemote.xcodeproj/project.pbxproj", "// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n#{objects.join("\n")}\n}; rootObject = #{oid(1)}; }\n")
File.write("#{root}/iPhoneRemote.xcodeproj/xcshareddata/xcschemes/iPhoneRemote.xcscheme", <<~XML)
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1430" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{oid(4)}" BuildableName="iPhone Remote.app" BlueprintName="iPhoneRemote" ReferencedContainer="container:iPhoneRemote.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{oid(4)}" BuildableName="iPhone Remote.app" BlueprintName="iPhoneRemote" ReferencedContainer="container:iPhoneRemote.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
XML
