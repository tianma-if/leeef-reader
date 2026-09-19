pluginManager.withPlugin("com.android.application") {
    extensions.configure<com.android.build.api.dsl.ApplicationExtension>("android") {
        buildTypes.named("debug") {
            applicationIdSuffix = ".debug"
        }
    }
}
