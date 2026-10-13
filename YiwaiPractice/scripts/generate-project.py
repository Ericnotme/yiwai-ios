#!/usr/bin/env python3
"""Generate a standalone Xcode project without installing build tooling."""
from pathlib import Path
import hashlib, json

root = Path(__file__).resolve().parents[1]
objects = {}
def uid(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def obj(key, isa, **fields):
    ident = uid(key); objects[ident] = dict(isa=isa,**fields); return ident
def ref(path, type, source='<group>'):
    return obj(path,'PBXFileReference',lastKnownFileType=type,path=path,sourceTree=source)
def build(file,tag): return obj('build'+tag+file,'PBXBuildFile',fileRef=file)
def phase(name,isa,files): return obj(name,isa,buildActionMask=2147483647,files=files,runOnlyForDeploymentPostprocessing=0)
def configs(name,settings):
    ids=[]
    for config in ['Debug','Release']:
        v=dict(settings)
        v['SWIFT_OPTIMIZATION_LEVEL']='-Onone' if config=='Debug' else '-O'
        if config=='Debug': v['ENABLE_TESTABILITY']='YES'; v['DEBUG_INFORMATION_FORMAT']='dwarf'; v['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
        ids.append(obj(name+config,'XCBuildConfiguration',buildSettings=v,name=config))
    return obj(name+'configs','XCConfigurationList',buildConfigurations=ids,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')

sourceFiles = [ref(str(p.relative_to(root)),'sourcecode.swift') for p in sorted((root/'Sources').glob('*.swift'))]
resources = [ref('Resources/'+p, 'sourcecode.javascript' if p.endswith('.js') else 'text') for p in ['chess.js','chess-bridge.js','seed-engine.js','game-review.js','stockfish-review.js','chess-LICENSE.txt']]
resources.append(ref('Resources/Stockfish','folder'))
assets=root/'Resources/Assets.xcassets/AppIcon.appiconset'; assets.mkdir(parents=True,exist_ok=True)
(assets/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2))
import shutil
shutil.copy(root/'Resources/app-icon.png',assets/'AppIcon.png')
(assets.parent/'Contents.json').write_text('{"info":{"author":"xcode","version":1}}')
resources.append(ref('Resources/Assets.xcassets','folder.assetcatalog'))
unitFiles=[ref(str(p.relative_to(root)),'sourcecode.swift') for p in sorted((root/'Tests').glob('*.swift'))]
uiFiles=[ref(str(p.relative_to(root)),'sourcecode.swift') for p in sorted((root/'UITests').glob('*.swift'))]
appProduct=obj('app-product','PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path='YiwaiPractice.app',sourceTree='BUILT_PRODUCTS_DIR')
unitProduct=obj('unit-product','PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex=0,path='YiwaiTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
uiProduct=obj('ui-product','PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex=0,path='YiwaiUITests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
products=obj('products','PBXGroup',children=[appProduct,unitProduct,uiProduct],name='Products',sourceTree='<group>')
main=obj('main','PBXGroup',children=sourceFiles+resources+unitFiles+uiFiles+[products],sourceTree='<group>')
projectConfig=configs('project',{'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','TARGETED_DEVICE_FAMILY':'1','CODE_SIGN_STYLE':'Manual','CODE_SIGNING_ALLOWED':'NO','ENABLE_USER_SCRIPT_SANDBOXING':'YES'})
base={'GENERATE_INFOPLIST_FILE':'YES','PRODUCT_NAME':'$(TARGET_NAME)','CURRENT_PROJECT_VERSION':'5','MARKETING_VERSION':'0.3.2'}
appConfig=configs('app',dict(base,PRODUCT_BUNDLE_IDENTIFIER='chat.weijiaxian.yiwai.practice',INFOPLIST_KEY_ITSAppUsesNonExemptEncryption='NO',INFOPLIST_KEY_CFBundleDisplayName='弈外练习',INFOPLIST_KEY_LSApplicationCategoryType='public.app-category.education',INFOPLIST_KEY_UILaunchScreen_Generation='YES',INFOPLIST_KEY_UIApplicationSceneManifest_Generation='YES',INFOPLIST_KEY_UISupportedInterfaceOrientations='UIInterfaceOrientationPortrait',ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon',LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/Frameworks'))
app=obj('app','PBXNativeTarget',buildConfigurationList=appConfig,buildPhases=[phase('app-src','PBXSourcesBuildPhase',[build(f,'app') for f in sourceFiles]),phase('app-fw','PBXFrameworksBuildPhase',[]),phase('app-res','PBXResourcesBuildPhase',[build(f,'res') for f in resources])],buildRules=[],dependencies=[],name='YiwaiPractice',productName='YiwaiPractice',productReference=appProduct,productType='com.apple.product-type.application')
def testTarget(name,files,product,settings,kind):
    dep=obj(name+'dep','PBXTargetDependency',target=app)
    return obj(name,'PBXNativeTarget',buildConfigurationList=configs(name,dict(base,**settings)),buildPhases=[phase(name+'src','PBXSourcesBuildPhase',[build(f,name) for f in files]),phase(name+'fw','PBXFrameworksBuildPhase',[])],buildRules=[],dependencies=[dep],name=name,productName=name,productReference=product,productType=kind)
unit=testTarget('YiwaiTests',unitFiles,unitProduct,{'PRODUCT_BUNDLE_IDENTIFIER':'chat.weijiaxian.yiwai.tests','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/YiwaiPractice.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/YiwaiPractice','BUNDLE_LOADER':'$(TEST_HOST)'},'com.apple.product-type.bundle.unit-test')
ui=testTarget('YiwaiUITests',uiFiles,uiProduct,{'PRODUCT_BUNDLE_IDENTIFIER':'chat.weijiaxian.yiwai.uitests','TEST_TARGET_NAME':'YiwaiPractice'},'com.apple.product-type.bundle.ui-testing')
project=obj('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2610','TargetAttributes':{app:{'CreatedOnToolsVersion':'26.1'},unit:{'CreatedOnToolsVersion':'26.1','TestTargetID':app},ui:{'CreatedOnToolsVersion':'26.1','TestTargetID':app}}},buildConfigurationList=projectConfig,compatibilityVersion='Xcode 14.0',developmentRegion='zh-Hans',hasScannedForEncodings=0,knownRegions=['zh-Hans','en','Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',targets=[app,unit,ui])
def serialize(value):
    if isinstance(value,dict): return '{\n'+''.join(json.dumps(str(k))+ ' = '+serialize(v)+';\n' for k,v in value.items())+'}'
    if isinstance(value,list): return '('+','.join(serialize(v) for v in value)+')'
    return json.dumps(value,ensure_ascii=False)
out=root/'YiwaiPractice.xcodeproj'; out.mkdir(exist_ok=True)
(out/'project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n')
schemes=out/'xcshareddata/xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
def entry(id,name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{id}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:YiwaiPractice.xcodeproj"/>'
(schemes/'YiwaiPractice.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2610" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{entry(app,'YiwaiPractice.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{entry(unit,'YiwaiTests.xctest')}</TestableReference><TestableReference skipped="NO">{entry(ui,'YiwaiUITests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{entry(app,'YiwaiPractice.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{entry(app,'YiwaiPractice.app')}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print(out)
