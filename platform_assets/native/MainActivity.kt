package fr.strasse.strasse

import android.content.ComponentName
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import java.security.MessageDigest
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

/**
 * Activité principale. Deux canaux natifs :
 *  - `fr.strasse.strasse/music` : liste des titres de l'appareil (MediaStore).
 *  - `fr.strasse.strasse/icons` : changement réel de l'icône de l'application (activity-alias).
 * AudioServiceActivity est requise par just_audio_background (lecture en arrière-plan).
 */
class MainActivity : AudioServiceActivity() {
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "fr.strasse.strasse/music").setMethodCallHandler { call, result ->
            when (call.method) {
                "listTracks" -> thread {
                    try {
                        val tracks = queryTracks()
                        main.post { result.success(tracks) }
                    } catch (e: SecurityException) {
                        main.post { result.error("permission", "Accès à la musique non autorisé.", null) }
                    } catch (e: Exception) {
                        main.post { result.error("query", e.message ?: "Lecture de la bibliothèque impossible.", null) }
                    }
                }
                "listPlaylists" -> result.success(emptyList<Any>())
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "fr.strasse.strasse/icons").setMethodCallHandler { call, result ->
            when (call.method) {
                "supported" -> result.success(true)
                "current" -> result.success(currentIcon(call.argument<List<String>>("names") ?: emptyList()))
                "set" -> {
                    val names = call.argument<List<String>>("names") ?: emptyList()
                    val target = call.argument<String>("name")
                    if (target == null || !names.contains(target)) {
                        result.error("invalid", "Icône inconnue.", null)
                    } else {
                        try {
                            setIcon(names, target)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("icon", e.message ?: "Changement d'icône impossible.", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "fr.strasse.strasse/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> result.success(Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls())
                "openInstallSettings" -> {
                    try {
                        val i = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("settings", e.message ?: "Réglage indisponible.", null)
                    }
                }
                // Vrai seulement si l'APK téléchargé est signé par la même clé que l'application installée.
                "sameSigner" -> {
                    val path = call.argument<String>("path")
                    if (path == null) result.error("invalid", "Chemin manquant.", null)
                    else thread {
                        val ok = try { sameSigner(path) } catch (e: Exception) { false }
                        main.post { result.success(ok) }
                    }
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("invalid", "Chemin manquant.", null)
                    } else {
                        try {
                            val file = File(path)
                            val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                            val i = Intent(Intent.ACTION_VIEW)
                            i.setDataAndType(uri, "application/vnd.android.package-archive")
                            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("install", e.message ?: "Installation impossible.", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun sameSigner(apkPath: String): Boolean {
        fun digests(info: PackageInfo?): Set<String> {
            if (info == null) return emptySet()
            val sigs: Array<Signature>? = if (Build.VERSION.SDK_INT >= 28) {
                val si = info.signingInfo
                if (si == null) null else if (si.hasMultipleSigners()) si.apkContentsSigners else si.signingCertificateHistory
            } else {
                @Suppress("DEPRECATION") info.signatures
            }
            val md = MessageDigest.getInstance("SHA-256")
            return sigs?.map { md.digest(it.toByteArray()).joinToString("") { b -> "%02x".format(b) } }?.toSet() ?: emptySet()
        }
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
        val mine = digests(packageManager.getPackageInfo(packageName, flags))
        val theirs = digests(packageManager.getPackageArchiveInfo(apkPath, flags))
        return mine.isNotEmpty() && theirs.isNotEmpty() && mine.intersect(theirs).isNotEmpty()
    }

    private fun queryTracks(): List<Map<String, Any?>> {
        val uri = if (Build.VERSION.SDK_INT >= 29) MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL) else MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID, MediaStore.Audio.Media.TITLE, MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM, MediaStore.Audio.Media.DURATION,
        )
        val out = ArrayList<Map<String, Any?>>()
        contentResolver.query(uri, projection, "${MediaStore.Audio.Media.IS_MUSIC} != 0", null, "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC")?.use { c ->
            val iId = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val iTitle = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val iArtist = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val iAlbum = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val iDur = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            while (c.moveToNext()) {
                val id = c.getLong(iId)
                val artist = c.getString(iArtist)
                out.add(
                    mapOf(
                        "id" to id.toString(),
                        "title" to (c.getString(iTitle) ?: ""),
                        // MediaStore renvoie « <unknown> » quand l'artiste est absent des métadonnées.
                        "artist" to (if (artist == null || artist == "<unknown>") "" else artist),
                        "album" to (c.getString(iAlbum) ?: ""),
                        "durationMs" to c.getLong(iDur),
                        "uri" to ContentUris.withAppendedId(uri, id).toString(),
                    ),
                )
            }
        }
        return out
    }

    // ---- Icônes alternatives : un activity-alias par icône, un seul activé à la fois.
    private fun alias(name: String) = ComponentName(packageName, "$packageName.icon.$name")

    private fun isEnabled(name: String): Boolean {
        val cn = alias(name)
        return when (packageManager.getComponentEnabledSetting(cn)) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> try {
                packageManager.getActivityInfo(cn, PackageManager.MATCH_DISABLED_COMPONENTS).enabled
            } catch (e: Exception) {
                false
            }
            else -> false
        }
    }

    private fun currentIcon(names: List<String>): String? = names.firstOrNull { isEnabled(it) }

    private fun setIcon(names: List<String>, target: String) {
        // On active la nouvelle icône avant de désactiver les autres : l'application reste toujours lançable.
        packageManager.setComponentEnabledSetting(alias(target), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
        for (n in names) {
            if (n != target) {
                packageManager.setComponentEnabledSetting(alias(n), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
            }
        }
    }
}
