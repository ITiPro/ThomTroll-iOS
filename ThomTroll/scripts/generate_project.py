"""Generate a dependency-free Xcode project. Run only when project structure changes."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent.parent
objects = {}

def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def obj(key_name, isa, **fields):
    key = uid(key_name)
    objects[key] = {'isa': isa, **fields}
    return key

def ref(path, kind):
    return obj('file:' + path, 'PBXFileReference', lastKnownFileType=kind, path=path, sourceTree='SOURCE_ROOT')

shared = ref('Shared/Library.swift', 'sourcecode.swift')
app_src = ref('App/ThomTrollApp.swift', 'sourcecode.swift')
kbd_src = ref('Keyboard/KeyboardViewController.swift', 'sourcecode.swift')
assets = ref('App/Assets.xcassets', 'folder.assetcatalog')
app_info = ref('App/Info.plist', 'text.plist.xml')
kbd_info = ref('Keyboard/Info.plist', 'text.plist.xml')
app_product = obj('app-product', 'PBXFileReference', explicitFileType='wrapper.application', path='ThomTroll.app', sourceTree='BUILT_PRODUCTS_DIR')
kbd_product = obj('kbd-product', 'PBXFileReference', explicitFileType='wrapper.app-extension', path='ThomTrollKeyboard.appex', sourceTree='BUILT_PRODUCTS_DIR')
products = obj('products', 'PBXGroup', children=[app_product, kbd_product], name='Products', sourceTree='<group>')
group = obj('main-group', 'PBXGroup', children=[app_src, kbd_src, shared, assets, app_info, kbd_info, products], sourceTree='<group>')

def buildfile(name, file, **extra):
    return obj(name, 'PBXBuildFile', fileRef=file, **extra)

def phase(name, kind, files):
    return obj(name, kind, buildActionMask='2147483647', files=files, runOnlyForDeploymentPostprocessing='0')

app_sources = phase('app-sources', 'PBXSourcesBuildPhase', [buildfile('app-source-build', app_src), buildfile('app-shared-build', shared)])
kbd_sources = phase('kbd-sources', 'PBXSourcesBuildPhase', [buildfile('kbd-source-build', kbd_src), buildfile('kbd-shared-build', shared)])
app_resources = phase('app-resources', 'PBXResourcesBuildPhase', [buildfile('app-assets-build', assets)])
kbd_resources = phase('kbd-resources', 'PBXResourcesBuildPhase', [])
app_frameworks = phase('app-frameworks', 'PBXFrameworksBuildPhase', [])
kbd_frameworks = phase('kbd-frameworks', 'PBXFrameworksBuildPhase', [])
embed = obj('embed-keyboard', 'PBXCopyFilesBuildPhase', buildActionMask='2147483647', dstPath='', dstSubfolderSpec='13',
            files=[buildfile('embed-build', kbd_product, settings={'ATTRIBUTES': ['CodeSignOnCopy', 'RemoveHeadersOnCopy']})],
            name='Embed Keyboard', runOnlyForDeploymentPostprocessing='0')

def config_list(name, base):
    configs = []
    for flavor in ['Debug', 'Release']:
        settings = dict(base)
        settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if flavor == 'Debug' else '-O'
        if flavor == 'Debug': settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
        configs.append(obj(name + flavor, 'XCBuildConfiguration', buildSettings=settings, name=flavor))
    return obj(name + '-configs', 'XCConfigurationList', buildConfigurations=configs, defaultConfigurationIsVisible='0', defaultConfigurationName='Release')

base = {'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '16.0', 'SWIFT_VERSION': '5.0',
        'CLANG_ENABLE_MODULES': 'YES', 'CODE_SIGN_STYLE': 'Automatic', 'TARGETED_DEVICE_FAMILY': '1,2',
        'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'SUPPORTS_MACCATALYST': 'NO',
        'GENERATE_INFOPLIST_FILE': 'NO', 'CURRENT_PROJECT_VERSION': '1', 'MARKETING_VERSION': '0.1'}
app_configs = config_list('app', {**base, 'PRODUCT_BUNDLE_IDENTIFIER': 'com.thomtroll.ios', 'PRODUCT_NAME': '$(TARGET_NAME)',
    'INFOPLIST_FILE': 'App/Info.plist', 'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES': 'YES',
    'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks'})
kbd_configs = config_list('kbd', {**base, 'PRODUCT_BUNDLE_IDENTIFIER': 'com.thomtroll.ios.keyboard', 'PRODUCT_NAME': '$(TARGET_NAME)',
    'INFOPLIST_FILE': 'Keyboard/Info.plist', 'APPLICATION_EXTENSION_API_ONLY': 'YES', 'SKIP_INSTALL': 'YES',
    'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'})
project_configs = config_list('project', {'CLANG_ENABLE_MODULES': 'YES', 'SWIFT_VERSION': '5.0', 'IPHONEOS_DEPLOYMENT_TARGET': '16.0'})
kbd_target = obj('keyboard-target', 'PBXNativeTarget', buildConfigurationList=kbd_configs, buildPhases=[kbd_sources, kbd_frameworks, kbd_resources],
                 buildRules=[], dependencies=[], name='ThomTrollKeyboard', productName='ThomTrollKeyboard', productReference=kbd_product, productType='com.apple.product-type.app-extension')
proxy = obj('kbd-proxy', 'PBXContainerItemProxy', containerPortal=uid('project'), proxyType='1', remoteGlobalIDString=kbd_target, remoteInfo='ThomTrollKeyboard')
dependency = obj('kbd-dependency', 'PBXTargetDependency', target=kbd_target, targetProxy=proxy)
app_target = obj('app-target', 'PBXNativeTarget', buildConfigurationList=app_configs, buildPhases=[app_sources, app_frameworks, app_resources, embed],
                 buildRules=[], dependencies=[dependency], name='ThomTroll', productName='ThomTroll', productReference=app_product, productType='com.apple.product-type.application')
project = obj('project', 'PBXProject', attributes={'LastUpgradeCheck': '1600', 'BuildIndependentTargetsInParallel': 'YES'},
    buildConfigurationList=project_configs, compatibilityVersion='Xcode 14.0', developmentRegion='ru', hasScannedForEncodings='0',
    knownRegions=['ru', 'en', 'Base'], mainGroup=group, productRefGroup=products, projectDirPath='', projectRoot='', targets=[app_target, kbd_target])

def serialize(value, depth=0):
    if isinstance(value, dict):
        return '{\n' + ''.join('\t' * (depth+1) + json.dumps(k) + ' = ' + serialize(v, depth+1) + ';\n' for k, v in value.items()) + '\t' * depth + '}'
    if isinstance(value, list): return '(' + ', '.join(serialize(v, depth) for v in value) + (',' if value else '') + ')'
    return json.dumps(str(value), ensure_ascii=True)

directory = ROOT / 'ThomTroll.xcodeproj'
directory.mkdir(exist_ok=True)
(directory/'project.pbxproj').write_text('// !$*UTF8*$!\n' + serialize({'archiveVersion': '1', 'classes': {}, 'objectVersion': '56', 'objects': objects, 'rootObject': project}) + '\n')
schemes = directory/'xcshareddata/xcschemes'; schemes.mkdir(parents=True, exist_ok=True)
(schemes/'ThomTroll.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="ThomTroll.app" BlueprintName="ThomTroll" ReferencedContainer="container:ThomTroll.xcodeproj"/>
    </BuildActionEntry></BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"/>
  <LaunchAction buildConfiguration="Debug" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="ThomTroll.app" BlueprintName="ThomTroll" ReferencedContainer="container:ThomTroll.xcodeproj"/></BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES"/>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print('Generated Xcode project with app + embedded keyboard; no App Groups or signing secrets.')
