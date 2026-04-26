#!/usr/bin/env ruby
# frozen_string_literal: true

require "xcodeproj"
require "fileutils"

project_path = "NewFileFromClipboard.xcodeproj"
FileUtils.rm_rf(project_path)

project = Xcodeproj::Project.new(project_path)
project.root_object.attributes["LastUpgradeCheck"] = "2640"
project.root_object.attributes["ORGANIZATIONNAME"] = "Eric Baruch"

sources = project.main_group.new_group("FinderExtension", "FinderExtension")
app_source = sources.new_file("NewFileFromClipboardApp.m")
extension_source = sources.new_file("NewFileFinderExtension.m")
sources.new_file("AppInfo.plist")
sources.new_file("ExtensionInfo.plist")
sources.new_file("App.entitlements")
sources.new_file("Extension.entitlements")

app_target = project.new_target(:application, "New File from Clipboard", :osx, "13.0")
extension_target = project.new_target(:app_extension, "NewFileFinderExtension", :osx, "13.0")

app_target.add_file_references([app_source])
extension_target.add_file_references([extension_source])
app_target.add_dependency(extension_target)

embed_extensions = app_target.new_copy_files_build_phase("Embed App Extensions")
embed_extensions.symbol_dst_subfolder_spec = :plug_ins
embed_extensions.add_file_reference(extension_target.product_reference, true)

def add_framework(project, target, framework)
  path = "System/Library/Frameworks/#{framework}.framework"
  ref = project.frameworks_group.files.find { |file| file.path == path }
  unless ref
    ref = project.frameworks_group.new_file(path)
    ref.source_tree = "SDKROOT"
  end
  target.frameworks_build_phase.add_file_reference(ref, true)
end

add_framework(project, app_target, "Cocoa")
add_framework(project, extension_target, "Cocoa")
add_framework(project, extension_target, "FinderSync")

project.build_configurations.each do |config|
  config.build_settings["CLANG_ENABLE_OBJC_ARC"] = "YES"
  config.build_settings["MACOSX_DEPLOYMENT_TARGET"] = "13.0"
  config.build_settings["SDKROOT"] = "macosx"
end

common = {
  "ALWAYS_SEARCH_USER_PATHS" => "NO",
  "CLANG_ENABLE_MODULES" => "YES",
  "CLANG_ENABLE_OBJC_ARC" => "YES",
  "CODE_SIGN_IDENTITY" => "Apple Development",
  "CODE_SIGN_STYLE" => "Automatic",
  "CURRENT_PROJECT_VERSION" => "1",
  "DEVELOPMENT_TEAM" => ENV.fetch("DEVELOPMENT_TEAM", "NSQB6N5244"),
  "ENABLE_HARDENED_RUNTIME" => "YES",
  "MACOSX_DEPLOYMENT_TARGET" => "13.0",
  "MARKETING_VERSION" => "1.0",
  "SDKROOT" => "macosx",
  "SWIFT_VERSION" => "5.0"
}

app_target.build_configurations.each do |config|
  config.build_settings.merge!(common)
  config.build_settings["CODE_SIGN_ENTITLEMENTS"] = "FinderExtension/App.entitlements"
  config.build_settings["INFOPLIST_FILE"] = "FinderExtension/AppInfo.plist"
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.ericbaruch.NewFileFromClipboard"
  config.build_settings["PRODUCT_NAME"] = "New File from Clipboard"
  config.build_settings["SKIP_INSTALL"] = "NO"
end

extension_target.build_configurations.each do |config|
  config.build_settings.merge!(common)
  config.build_settings["APPLICATION_EXTENSION_API_ONLY"] = "YES"
  config.build_settings["CODE_SIGN_ENTITLEMENTS"] = "FinderExtension/Extension.entitlements"
  config.build_settings["INFOPLIST_FILE"] = "FinderExtension/ExtensionInfo.plist"
  config.build_settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks"
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.ericbaruch.NewFileFromClipboard.FinderExtension"
  config.build_settings["PRODUCT_NAME"] = "NewFileFinderExtension"
  config.build_settings["SKIP_INSTALL"] = "YES"
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app_target)
scheme.set_launch_target(app_target)
scheme.save_as(project_path, "New File from Clipboard", true)
