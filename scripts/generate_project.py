#!/usr/bin/env python3
"""Generate a dependency-free Xcode project with stable IDs. Run after adding files."""
import hashlib
from pathlib import Path
root = Path(__file__).resolve().parent.parent
objects = {}
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def add(key, value):
    ident = uid(key); objects[ident] = value; return ident
def arr(items): return '(' + ', '.join(items) + (',' if items else '') + ')'
def quoted(s): return '"' + str(s).replace('"', '\\"') + '"'
def visible(p): return p.is_file() and not p.name.startswith('.')  # skip .DS_Store & co.
shared = sorted(root.glob('Shared/**/*.swift'))  # protocol code compiled into both apps
mac_sources = sorted(root.glob('MacPrompter/**/*.swift'))
resources = sorted(p for p in root.glob('MacPrompter/Resources/**/*') if visible(p))
tests = sorted(root.glob('MacPrompterTests/*.swift'))
remote_sources = sorted(root.glob('MacPrompterRemote/**/*.swift'))
remote_resources = sorted(root.glob('MacPrompterRemote/*.xcassets'))
# stdio MCP helper for Claude Desktop/Cowork, embedded in the app; reuses the bridge and JSON code.
helper_sources = sorted(root.glob('MacPrompterMCP/*.swift')) + [root/'MacPrompter/Services/MCPBridge.swift', root/'MacPrompter/Core/JSONValue.swift']
kinds = {'.swift': 'sourcecode.swift', '.icns': 'image.icns', '.xcassets': 'folder.assetcatalog', '.xcconfig': 'text.xcconfig', '.plist': 'text.plist.xml'}
def fileref(p):
    path = str(p.relative_to(root))
    return add(path, '{isa = PBXFileReference; lastKnownFileType = '+kinds.get(p.suffix, 'file')+'; path = '+quoted(path)+'; sourceTree = SOURCE_ROOT; }')
def refs(paths, phase):
    builds = []; files = []
    for p in paths:
        ref = fileref(p); files.append(ref)
        builds.append(add(phase+str(p.relative_to(root)), '{isa = PBXBuildFile; fileRef = '+ref+'; }'))
    return builds, files
sb,sf = refs(mac_sources,'source'); shb,shf = refs(shared,'source'); rb,rf = refs(resources,'resource'); tb,tf = refs(tests,'test')
# Speech fixtures are generated locally by scripts/make_fixtures.sh (not committed), so list them by name.
fixtures = {root/'MacPrompterTests/Fixtures'/(n+'.aiff') for n in ('de', 'en', 'de-aside', 'en-aside')}
fixtures |= {p for p in root.glob('MacPrompterTests/Fixtures/*') if visible(p)}
trb,trf = refs(sorted(fixtures), 'testresource')
mb,mf = refs(remote_sources,'remotesource'); mshb,_ = refs(shared,'remotesource'); mrb,mrf = refs(remote_resources,'remoteresource')
hb,hf = refs(helper_sources,'helpersource'); helperentitlements = fileref(root/'MacPrompterMCP/MacPrompterMCP.entitlements')
signing = fileref(root/'MacPrompterRemote/Signing.xcconfig'); remoteplist = fileref(root/'MacPrompterRemote/Info.plist')
def phase(name, kind, builds): return add(name, '{isa = '+kind+'; buildActionMask = 2147483647; files = '+arr(builds)+'; runOnlyForDeploymentPostprocessing = 0; }')
hsrc = phase('helpersrc','PBXSourcesBuildPhase',hb); hfw = phase('helperfw','PBXFrameworksBuildPhase',[])
asrc = phase('appsrc','PBXSourcesBuildPhase',sb+shb); arsc = phase('apprsc','PBXResourcesBuildPhase',rb); afw = phase('appfw','PBXFrameworksBuildPhase',[])
trsc = phase('testrsc','PBXResourcesBuildPhase',trb)
tsrc = phase('testsrc','PBXSourcesBuildPhase',tb); tfw = phase('testfw','PBXFrameworksBuildPhase',[])
msrc = phase('remotesrc','PBXSourcesBuildPhase',mb+mshb); mrsc = phase('remotersc','PBXResourcesBuildPhase',mrb); mfw = phase('remotefw','PBXFrameworksBuildPhase',[])
aproduct = add('appProduct','{isa = PBXFileReference; explicitFileType = wrapper.application; path = macprompter.app; sourceTree = BUILT_PRODUCTS_DIR; }')
mproduct = add('remoteProduct','{isa = PBXFileReference; explicitFileType = wrapper.application; path = "macprompter Remote.app"; sourceTree = BUILT_PRODUCTS_DIR; }')
hproduct = add('helperProduct','{isa = PBXFileReference; explicitFileType = "compiled.mach-o.executable"; path = "macprompter-mcp"; sourceTree = BUILT_PRODUCTS_DIR; }')
hembed = add('helperEmbed','{isa = PBXBuildFile; fileRef = '+hproduct+'; settings = {ATTRIBUTES = (CodeSignOnCopy, ); }; }')
aembed = add('appembed','{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = Contents/Helpers; dstSubfolderSpec = 1; files = '+arr([hembed])+'; name = "Embed Helpers"; runOnlyForDeploymentPostprocessing = 0; }')
tproduct = add('testProduct','{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = MacPrompterTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }')
def configs(name, shared, debug=None, base=None):
    ids=[]
    for config in ['Debug','Release']:
        values=dict(shared)
        values.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if config=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if config=='Debug' else 'dwarf-with-dsym'})
        # Release builds must not let a debugger attach (get-task-allow); notarization rejects it too.
        values['CODE_SIGN_INJECT_BASE_ENTITLEMENTS']='YES' if config=='Debug' else 'NO'
        if config=='Debug': values.update(debug or {})
        content=' '.join(k+' = '+quoted(v)+';' for k,v in values.items())
        baseref='baseConfigurationReference = '+base+'; ' if base else ''
        ids.append(add(name+config,'{isa = XCBuildConfiguration; '+baseref+'buildSettings = {'+content+'}; name = '+config+'; }'))
    return add(name+'configs','{isa = XCConfigurationList; buildConfigurations = '+arr(ids)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }')
pc=configs('project',{'SDKROOT':'macosx','MACOSX_DEPLOYMENT_TARGET':'26.0','SWIFT_VERSION':'6.0','CLANG_ENABLE_MODULES':'YES','ENABLE_USER_SCRIPT_SANDBOXING':'YES','SWIFT_STRICT_CONCURRENCY':'complete','MARKETING_VERSION':'1.1.0','CURRENT_PROJECT_VERSION':'2'},{'ENABLE_TESTABILITY':'YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG'})
ac=configs('app',{'PRODUCT_NAME':'macprompter','PRODUCT_MODULE_NAME':'MacPrompter','PRODUCT_BUNDLE_IDENTIFIER':'io.github.fng-2002.macprompter','INFOPLIST_FILE':'MacPrompter/Info.plist','CODE_SIGN_ENTITLEMENTS':'MacPrompter/MacPrompter.entitlements','CODE_SIGN_STYLE':'Manual','CODE_SIGN_IDENTITY':'-','COMBINE_HIDPI_IMAGES':'YES','ENABLE_HARDENED_RUNTIME':'YES','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks','SWIFT_EMIT_LOC_STRINGS':'YES','COPY_PHASE_STRIP':'NO'},
    # Debug is also the test host: only it may open outgoing connections (loopback remote test).
    {'CODE_SIGN_ENTITLEMENTS':'MacPrompter/MacPrompterDebug.entitlements'})
# Own sandbox with outgoing connections only, to reach the app on 127.0.0.1 (ADR-23).
hc=configs('helper',{'PRODUCT_NAME':'macprompter-mcp','PRODUCT_BUNDLE_IDENTIFIER':'io.github.fng-2002.macprompter.mcp','GENERATE_INFOPLIST_FILE':'YES','CREATE_INFOPLIST_SECTION_IN_BINARY':'YES','INFOPLIST_KEY_CFBundleDisplayName':'macprompter MCP','CODE_SIGN_ENTITLEMENTS':'MacPrompterMCP/MacPrompterMCP.entitlements','CODE_SIGN_STYLE':'Manual','CODE_SIGN_IDENTITY':'-','ENABLE_HARDENED_RUNTIME':'YES','SKIP_INSTALL':'YES'})
tc=configs('test',{'PRODUCT_NAME':'MacPrompterTests','PRODUCT_BUNDLE_IDENTIFIER':'io.github.fng-2002.macprompter.tests','GENERATE_INFOPLIST_FILE':'YES','CODE_SIGN_IDENTITY':'-','CODE_SIGN_STYLE':'Manual','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/macprompter.app/Contents/MacOS/macprompter','BUNDLE_LOADER':'$(TEST_HOST)','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks'})
# Signing and bundle ID live in MacPrompterRemote/Signing.xcconfig: target
# settings would override it, and an untracked include adds a team for devices.
mc=configs('remote',{'SDKROOT':'iphoneos','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','IPHONEOS_DEPLOYMENT_TARGET':'26.0','TARGETED_DEVICE_FAMILY':'1','PRODUCT_NAME':'macprompter Remote','PRODUCT_MODULE_NAME':'MacPrompterRemote','INFOPLIST_FILE':'MacPrompterRemote/Info.plist','GENERATE_INFOPLIST_FILE':'YES','INFOPLIST_KEY_CFBundleDisplayName':'macprompter Remote','INFOPLIST_KEY_UILaunchScreen_Generation':'YES','INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES','INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents':'YES','INFOPLIST_KEY_UISupportedInterfaceOrientations':'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight','INFOPLIST_KEY_LSApplicationCategoryType':'public.app-category.productivity','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks','SWIFT_EMIT_LOC_STRINGS':'YES'},base=signing)
aid=uid('appTarget'); tid=uid('testTarget'); mid=uid('remoteTarget'); hid=uid('helperTarget'); pid=uid('project')
proxy=add('proxy','{isa = PBXContainerItemProxy; containerPortal = '+pid+'; proxyType = 1; remoteGlobalIDString = '+aid+'; remoteInfo = macprompter; }')
dep=add('dependency','{isa = PBXTargetDependency; target = '+aid+'; targetProxy = '+proxy+'; }')
hproxy=add('helperProxy','{isa = PBXContainerItemProxy; containerPortal = '+pid+'; proxyType = 1; remoteGlobalIDString = '+hid+'; remoteInfo = "macprompter-mcp"; }')
hdep=add('helperDependency','{isa = PBXTargetDependency; target = '+hid+'; targetProxy = '+hproxy+'; }')
add('appTarget','{isa = PBXNativeTarget; buildConfigurationList = '+ac+'; buildPhases = '+arr([asrc,afw,arsc,aembed])+'; buildRules = (); dependencies = '+arr([hdep])+'; name = macprompter; productName = macprompter; productReference = '+aproduct+'; productType = "com.apple.product-type.application"; }')
add('testTarget','{isa = PBXNativeTarget; buildConfigurationList = '+tc+'; buildPhases = '+arr([tsrc,tfw,trsc])+'; buildRules = (); dependencies = '+arr([dep])+'; name = MacPrompterTests; productName = MacPrompterTests; productReference = '+tproduct+'; productType = "com.apple.product-type.bundle.unit-test"; }')
add('helperTarget','{isa = PBXNativeTarget; buildConfigurationList = '+hc+'; buildPhases = '+arr([hsrc,hfw])+'; buildRules = (); dependencies = (); name = "macprompter-mcp"; productName = "macprompter-mcp"; productReference = '+hproduct+'; productType = "com.apple.product-type.tool"; }')
add('remoteTarget','{isa = PBXNativeTarget; buildConfigurationList = '+mc+'; buildPhases = '+arr([msrc,mfw,mrsc])+'; buildRules = (); dependencies = (); name = "macprompter Remote"; productName = "macprompter Remote"; productReference = '+mproduct+'; productType = "com.apple.product-type.application"; }')
products=add('products','{isa = PBXGroup; children = '+arr([aproduct,hproduct,mproduct,tproduct])+'; name = Products; sourceTree = "<group>"; }')
sourcegroup=add('sources','{isa = PBXGroup; children = '+arr(sf+rf)+'; name = MacPrompter; sourceTree = "<group>"; }')
sharedgroup=add('shared','{isa = PBXGroup; children = '+arr(shf)+'; name = Shared; sourceTree = "<group>"; }')
helpergroup=add('helper','{isa = PBXGroup; children = '+arr([f for f,p in zip(hf,helper_sources) if p.parent.name=='MacPrompterMCP']+[helperentitlements])+'; name = MacPrompterMCP; sourceTree = "<group>"; }')
remotegroup=add('remote','{isa = PBXGroup; children = '+arr(mf+mrf+[remoteplist,signing])+'; name = MacPrompterRemote; sourceTree = "<group>"; }')
testgroup=add('tests','{isa = PBXGroup; children = '+arr(tf+trf)+'; name = Tests; sourceTree = "<group>"; }')
group=add('rootgroup','{isa = PBXGroup; children = '+arr([sourcegroup,sharedgroup,helpergroup,remotegroup,testgroup,products])+'; sourceTree = "<group>"; }')
add('project','{isa = PBXProject; attributes = {LastSwiftUpdateCheck = 2620; LastUpgradeCheck = 2620; }; buildConfigurationList = '+pc+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = de; hasScannedForEncodings = 0; knownRegions = (de,en,Base); mainGroup = '+group+'; productRefGroup = '+products+'; projectDirPath = ""; projectRoot = ""; targets = '+arr([aid,hid,tid,mid])+'; }')
project=root/'MacPrompter.xcodeproj'; project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(k+' = '+v+';' for k,v in objects.items())+'\n}; rootObject = '+pid+'; }\n')
schemes=project/'xcshareddata/xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
def ref(i,n): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{i}" BuildableName="{n}" BlueprintName="{n.rsplit(".",1)[0]}" ReferencedContainer="container:MacPrompter.xcodeproj"/>'
def scheme(target, product, testables=''):
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2620" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref(target,product)}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>{testables}</Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(target,product)}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(target,product)}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(schemes/'macprompter.xcscheme').write_text(scheme(aid,'macprompter.app',f'<TestableReference skipped="NO">{ref(tid,"MacPrompterTests.xctest")}</TestableReference>'))
(schemes/'macprompter Remote.xcscheme').write_text(scheme(mid,'macprompter Remote.app'))
print('Generated MacPrompter.xcodeproj')
