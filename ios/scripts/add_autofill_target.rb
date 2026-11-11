# Adaugă în proiectul Xcode extensiile Notițe și drepturile aplicației:
# - AutoFill (completarea parolelor în iOS);
# - SafariExtension (salvarea parolelor pe site-uri în Safari; resursele JS
#   sunt copiate din extension/ de workflow, în SafariExtension/Resources).
# Rulează în build-ul de pe GitHub (macOS), înainte de `flutter build ipa`;
# ce există deja nu se mai adaugă.
require 'xcodeproj'

ios = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(ios, 'Runner.xcodeproj'))
runner = project.targets.find { |t| t.name == 'Runner' }

runner.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

def embed_phase(runner)
  existing = runner.copy_files_build_phases.find do |p|
    p.name == 'Embed Foundation Extensions'
  end
  return existing if existing

  phase = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  phase.symbol_dst_subfolder_spec = :plug_ins
  # Înaintea scripturilor Flutter de la final („Thin Binary”), altfel Xcode
  # raportează o dependență circulară.
  phases = runner.build_phases
  phases.delete(phase)
  thin = phases.index { |p| p.respond_to?(:name) && p.name.to_s.include?('Thin Binary') }
  phases.insert(thin || phases.length, phase)
  phase
end

def add_extension(project, runner, name:, bundle_id:, profile:, swift:,
                  entitlements: nil, resources: nil)
  return if project.targets.any? { |t| t.name == name }

  ext = project.new_target(:app_extension, name, :ios, '15.5', nil, :swift)
  unless ext.build_configurations.any? { |c| c.name == 'Profile' }
    ext.add_build_configuration('Profile', :release)
  end

  group = project.main_group.new_group(name, name)
  source = group.new_reference(swift)
  group.new_reference('Info.plist')
  group.new_reference(entitlements) if entitlements
  xcconfig = group.new_reference("#{name}.xcconfig")
  ext.add_file_references([source])
  if resources
    folder = group.new_reference(resources)
    folder.last_known_file_type = 'folder'
    ext.resources_build_phase.add_file_reference(folder, true)
  end

  ext.build_configurations.each do |c|
    c.base_configuration_reference = xcconfig
    s = c.build_settings
    s['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id
    s['PRODUCT_NAME'] = '$(TARGET_NAME)'
    s['INFOPLIST_FILE'] = "#{name}/Info.plist"
    s['GENERATE_INFOPLIST_FILE'] = 'NO'
    s['CODE_SIGN_ENTITLEMENTS'] = "#{name}/#{entitlements}" if entitlements
    s['SWIFT_VERSION'] = '5.0'
    s['IPHONEOS_DEPLOYMENT_TARGET'] = '15.5'
    s['TARGETED_DEVICE_FAMILY'] = '1,2'
    s['DEVELOPMENT_TEAM'] = 'FUR5C9CYR8'
    s['SKIP_INSTALL'] = 'YES'
    s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
    s['LD_RUNPATH_SEARCH_PATHS'] = [
      '$(inherited)', '@executable_path/Frameworks',
      '@executable_path/../../Frameworks'
    ]
    if c.name == 'Debug'
      s['CODE_SIGN_STYLE'] = 'Automatic'
    else
      s['CODE_SIGN_STYLE'] = 'Manual'
      s['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
      s['CODE_SIGN_IDENTITY[sdk=iphoneos*]'] = 'Apple Distribution'
      s['PROVISIONING_PROFILE_SPECIFIER'] = profile
    end
  end

  # Aplicația o construiește și o pune în pachet (PlugIns/).
  runner.add_dependency(ext)
  file = embed_phase(runner).add_file_reference(ext.product_reference, true)
  file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end

add_extension(project, runner,
              name: 'AutoFill',
              bundle_id: 'com.kappado.notite.AutoFill',
              profile: 'Notite AutoFill AppStore',
              swift: 'CredentialProviderViewController.swift',
              entitlements: 'AutoFill.entitlements')

if File.directory?(File.join(ios, 'SafariExtension', 'Resources'))
  add_extension(project, runner,
                name: 'SafariExtension',
                bundle_id: 'com.kappado.notite.Safari',
                profile: 'Notite Safari AppStore',
                swift: 'SafariWebExtensionHandler.swift',
                resources: 'Resources')
end

project.save
puts 'Extensii: proiect pregătit'
