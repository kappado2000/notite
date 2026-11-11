# Adaugă în proiectul Xcode extensia AutoFill (completarea parolelor în iOS)
# și drepturile aplicației. Rulează în build-ul de pe GitHub (macOS), înainte
# de `flutter build ipa`; dacă extensia există deja, nu schimbă nimic.
require 'xcodeproj'

ios = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(ios, 'Runner.xcodeproj'))
runner = project.targets.find { |t| t.name == 'Runner' }

runner.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

unless project.targets.any? { |t| t.name == 'AutoFill' }
  ext = project.new_target(:app_extension, 'AutoFill', :ios, '15.5', nil, :swift)
  unless ext.build_configurations.any? { |c| c.name == 'Profile' }
    ext.add_build_configuration('Profile', :release)
  end

  group = project.main_group.new_group('AutoFill', 'AutoFill')
  source = group.new_reference('CredentialProviderViewController.swift')
  group.new_reference('Info.plist')
  group.new_reference('AutoFill.entitlements')
  xcconfig = group.new_reference('AutoFill.xcconfig')
  ext.add_file_references([source])

  ext.build_configurations.each do |c|
    c.base_configuration_reference = xcconfig
    s = c.build_settings
    s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.kappado.notite.AutoFill'
    s['PRODUCT_NAME'] = '$(TARGET_NAME)'
    s['INFOPLIST_FILE'] = 'AutoFill/Info.plist'
    s['GENERATE_INFOPLIST_FILE'] = 'NO'
    s['CODE_SIGN_ENTITLEMENTS'] = 'AutoFill/AutoFill.entitlements'
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
      s['PROVISIONING_PROFILE_SPECIFIER'] = 'Notite AutoFill AppStore'
    end
  end

  # Aplicația o construiește și o pune în pachet (PlugIns/).
  runner.add_dependency(ext)
  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins
  file = embed.add_file_reference(ext.product_reference, true)
  file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

  # Înaintea scripturilor Flutter de la final („Thin Binary”), altfel Xcode
  # raportează o dependență circulară.
  phases = runner.build_phases
  phases.delete(embed)
  thin = phases.index { |p| p.respond_to?(:name) && p.name.to_s.include?('Thin Binary') }
  phases.insert(thin || phases.length, embed)
end

project.save
puts 'AutoFill: proiect pregătit'
