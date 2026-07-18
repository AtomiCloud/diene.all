import com.android.build.gradle.AppExtension

val android = project.extensions.getByType(AppExtension::class.java)

android.apply {
    flavorDimensions("flavor-type")

    productFlavors {
        create("lapras") {
            dimension = "flavor-type"
            applicationId = "cloud.atomi.lapras.platform.service.app"
            resValue(type = "string", name = "app_name", value = "Diene Mobile (Lapras)")
            manifestPlaceholders["appName"] = "Diene Mobile (Lapras)"
            manifestPlaceholders["logtoRedirectScheme"] = "cloud.atomi.lapras.platform.service.app"
        }
        create("pichu") {
            dimension = "flavor-type"
            applicationId = "cloud.atomi.pichu.platform.service.app"
            resValue(type = "string", name = "app_name", value = "Diene Mobile (Pichu)")
            manifestPlaceholders["appName"] = "Diene Mobile (Pichu)"
            manifestPlaceholders["logtoRedirectScheme"] = "cloud.atomi.pichu.platform.service.app"
        }
        create("pikachu") {
            dimension = "flavor-type"
            applicationId = "cloud.atomi.pikachu.platform.service.app"
            resValue(type = "string", name = "app_name", value = "Diene Mobile (Pikachu)")
            manifestPlaceholders["appName"] = "Diene Mobile (Pikachu)"
            manifestPlaceholders["logtoRedirectScheme"] = "cloud.atomi.pikachu.platform.service.app"
        }
        create("raichu") {
            dimension = "flavor-type"
            applicationId = "cloud.atomi.raichu.platform.service.app"
            resValue(type = "string", name = "app_name", value = "Diene Mobile")
            manifestPlaceholders["appName"] = "Diene Mobile"
            manifestPlaceholders["logtoRedirectScheme"] = "cloud.atomi.raichu.platform.service.app"
        }
    }

    buildFeatures.resValues = true
}
