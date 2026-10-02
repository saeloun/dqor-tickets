"""Regenerate the dependency-free Xcode project. Python standard library only."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parent
objects = {}
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name, body):
    key = ident(name); objects[key] = body; return key
def ref(name): return ident(name)
def seq(values): return '(' + ', '.join(values) + (',' if values else '') + ')'
def config(name, settings):
    return add(name, '{isa = XCBuildConfiguration; buildSettings = {' + ''.join(f'{k} = {v};' for k,v in settings.items()) + '}; name = ' + name.split('/')[-1] + ';}')
def configs(name, settings):
    ids = [config(name+'/'+kind, dict(settings, **({'SWIFT_OPTIMIZATION_LEVEL':'"-Onone"','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG'} if kind == 'Debug' else {}))) for kind in ['Debug','Release']]
    return add(name+'/configs', '{isa = XCConfigurationList; buildConfigurations = '+seq(ids)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
project_configs = configs('project', {'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','SWIFT_STRICT_CONCURRENCY':'targeted','DEBUG_INFORMATION_FORMAT':'dwarf'})
products=[]; groups=[]; targets=[]
for target,folder,kind in [('DQORStaff','Sources','application'),('DQORStaffTests','Tests','bundle.unit-test'),('DQORStaffUITests','UITests','bundle.ui-testing')]:
    files=[]; builds=[]
    for p in sorted((root/folder).glob('*.swift')):
        f=add(str(p.relative_to(root)), '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "'+p.name+'"; sourceTree = "<group>";}')
        files.append(f); builds.append(add('build/'+p.name,'{isa = PBXBuildFile; fileRef = '+f+';}'))
    groups.append(add(folder,'{isa = PBXGroup; children = '+seq(files)+'; path = '+folder+'; sourceTree = "<group>";}'))
    ext='app' if kind=='application' else 'xctest'
    prod=add(target+'/product','{isa = PBXFileReference; explicitFileType = '+('wrapper.application' if ext=='app' else 'wrapper.cfbundle')+'; path = '+target+'.'+ext+'; sourceTree = BUILT_PRODUCTS_DIR;}'); products.append(prod)
    phase=add(target+'/sources','{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+seq(builds)+'; runOnlyForDeploymentPostprocessing = 0;}')
    settings={'PRODUCT_NAME':'"$(TARGET_NAME)"','PRODUCT_BUNDLE_IDENTIFIER':'org.dqor.staff'+('' if ext=='app' else '.'+folder.lower()),'GENERATE_INFOPLIST_FILE':'YES','TARGETED_DEVICE_FAMILY':'"1,2"','CODE_SIGN_STYLE':'Automatic','CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'0.1.0','ENABLE_TESTABILITY':'YES'}
    if ext=='app': settings.update({'INFOPLIST_KEY_NSCameraUsageDescription':'"Scan attendee ticket QR codes to prepare a check-in batch."','INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES','INFOPLIST_KEY_UILaunchScreen_Generation':'YES','INFOPLIST_KEY_CFBundleDisplayName':'"DQOR Staff"','INFOPLIST_KEY_UISupportedInterfaceOrientations':'"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"'})
    elif folder=='Tests': settings.update({'TEST_HOST':'"$(BUILT_PRODUCTS_DIR)/DQORStaff.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/DQORStaff"','BUNDLE_LOADER':'"$(TEST_HOST)"'})
    else: settings['TEST_TARGET_NAME']='DQORStaff'
    cfg=configs(target,settings); deps=[]
    if ext!='app':
        proxy=add(target+'/proxy','{isa = PBXContainerItemProxy; containerPortal = '+ref('project')+'; proxyType = 1; remoteGlobalIDString = '+ref('DQORStaff/target')+'; remoteInfo = DQORStaff;}')
        deps=[add(target+'/dependency','{isa = PBXTargetDependency; target = '+ref('DQORStaff/target')+'; targetProxy = '+proxy+';}')]
    targets.append(add(target+'/target','{isa = PBXNativeTarget; buildConfigurationList = '+cfg+'; buildPhases = '+seq([phase])+'; buildRules = (); dependencies = '+seq(deps)+'; name = '+target+'; productName = '+target+'; productReference = '+prod+'; productType = "com.apple.product-type.'+kind+'";}'))
products_group=add('products','{isa = PBXGroup; children = '+seq(products)+'; name = Products; sourceTree = "<group>";}')
main=add('main','{isa = PBXGroup; children = '+seq(groups+[products_group])+'; sourceTree = "<group>";}')
add('project','{isa = PBXProject; attributes = {LastUpgradeCheck = 2700;}; buildConfigurationList = '+project_configs+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = '+main+'; productRefGroup = '+products_group+'; projectDirPath = ""; projectRoot = ""; targets = '+seq(targets)+';}')
proj=root/'DQORStaff.xcodeproj'; proj.mkdir(exist_ok=True)
(proj/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+ '\n'.join(k+' = '+v+';' for k,v in objects.items())+'\n}; rootObject = '+ref('project')+';}\n')
scheme=proj/'xcshareddata/xcschemes'; scheme.mkdir(parents=True,exist_ok=True)
def buildable(target): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref(target+"/target")}" BuildableName="{target}.{ "app" if target=="DQORStaff" else "xctest"}" BlueprintName="{target}" ReferencedContainer="container:DQORStaff.xcodeproj"/>'
(scheme/'DQORStaff.xcscheme').write_text('<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">'+buildable('DQORStaff')+'</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>'+''.join('<TestableReference skipped="NO">'+buildable(t)+'</TestableReference>' for t in ['DQORStaffTests','DQORStaffUITests'])+'</Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">'+buildable('DQORStaff')+'</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">'+buildable('DQORStaff')+'</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>')
