package com.uteq.practica1112.smartwatch_auth

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate

/**
 * Prácticas 13 y 14 / rúbrica D: el reloj lee SENSORES REALES de Android (ritmo cardíaco, contador de pasos y batería) en lugar de
 * inventar valores. Funciona igual en un reloj físico con Wear OS y en el emulador (Extended controls → Virtual sensors).
 *
 * Canal «vitasync/sensores»:
 *   · estado         → qué sensores hay y qué permisos están concedidos
 *   · pedirPermisos  → muestra el diálogo del sistema; responde con el estado resultante
 *   · leer           → una lectura (ritmo cardíaco, pasos del día, batería); null en lo que no se pudo medir
 */
class MainActivity : FlutterFragmentActivity() {
    private val canal = "vitasync/sensores"
    private val codigoPermisos = 4021
    private var respuestaPermisos: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Evita que datos médicos/personales queden expuestos en capturas de
        // pantalla o en la miniatura de la app en "Recientes".
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canal).setMethodCallHandler { llamada, resultado ->
            when (llamada.method) {
                "estado" -> resultado.success(estado())
                "pedirPermisos" -> pedirPermisos(resultado)
                "leer" -> leer(resultado)
                else -> resultado.notImplemented()
            }
        }
    }

    /** Permiso del sensor de ritmo cardíaco: BODY_SENSORS hasta Android 15; en Android 16 (API 36) lo sustituye el permiso de salud. */
    private fun permisoCardiaco(): String =
        if (Build.VERSION.SDK_INT >= 36) "android.permission.health.READ_HEART_RATE" else Manifest.permission.BODY_SENSORS

    private fun permisosNecesarios(): List<String> {
        val lista = mutableListOf(permisoCardiaco())
        if (Build.VERSION.SDK_INT >= 29) lista.add(Manifest.permission.ACTIVITY_RECOGNITION)
        return lista
    }

    private fun concedido(permiso: String) =
        ContextCompat.checkSelfPermission(this, permiso) == PackageManager.PERMISSION_GRANTED

    private fun estado(): Map<String, Any> {
        val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        return mapOf(
            "frecuenciaDisponible" to (sm.getDefaultSensor(Sensor.TYPE_HEART_RATE) != null),
            "pasosDisponible" to (sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER) != null),
            "permisoCardiaco" to concedido(permisoCardiaco()),
            "permisoActividad" to (Build.VERSION.SDK_INT < 29 || concedido(Manifest.permission.ACTIVITY_RECOGNITION)),
            "bateria" to bateria(),
        )
    }

    private fun pedirPermisos(resultado: MethodChannel.Result) {
        val faltan = permisosNecesarios().filter { !concedido(it) }
        if (faltan.isEmpty()) { resultado.success(estado()); return }
        respuestaPermisos?.success(estado()) // una petición anterior sin contestar
        respuestaPermisos = resultado
        ActivityCompat.requestPermissions(this, faltan.toTypedArray(), codigoPermisos)
    }

    override fun onRequestPermissionsResult(codigo: Int, permisos: Array<out String>, resultados: IntArray) {
        super.onRequestPermissionsResult(codigo, permisos, resultados)
        if (codigo == codigoPermisos) {
            respuestaPermisos?.success(estado())
            respuestaPermisos = null
        }
    }

    private fun bateria(): Int {
        val intento: Intent? = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val nivel = intento?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val escala = intento?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        return if (nivel >= 0 && escala > 0) (nivel * 100 / escala) else -1
    }

    /** Una lectura: espera hasta 10 s a la primera muestra válida de cada sensor (el ritmo cardíaco tarda unos segundos en estabilizarse). */
    private fun leer(resultado: MethodChannel.Result) {
        val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val manejador = Handler(Looper.getMainLooper())
        val datos = mutableMapOf<String, Any?>("frecuenciaCardiaca" to null, "pasos" to null, "bateria" to bateria())
        val escuchas = mutableListOf<SensorEventListener>()
        var pendientes = 0
        var respondido = false

        fun terminar() {
            if (respondido) return
            respondido = true
            escuchas.forEach { sm.unregisterListener(it) }
            resultado.success(datos)
        }

        fun escuchar(tipo: Int, clave: String, convertir: (Float) -> Any?) {
            val sensor = sm.getDefaultSensor(tipo) ?: return
            val permiso = if (tipo == Sensor.TYPE_HEART_RATE) permisoCardiaco() else Manifest.permission.ACTIVITY_RECOGNITION
            if (tipo != Sensor.TYPE_HEART_RATE && Build.VERSION.SDK_INT < 29) {
                // sin permiso en versiones antiguas
            } else if (!concedido(permiso)) return
            pendientes++
            val escucha = object : SensorEventListener {
                override fun onSensorChanged(evento: SensorEvent) {
                    val valor = convertir(evento.values[0]) ?: return // muestra no válida: se sigue esperando
                    datos[clave] = valor
                    sm.unregisterListener(this)
                    if (--pendientes == 0) terminar()
                }
                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
            }
            escuchas.add(escucha)
            sm.registerListener(escucha, sensor, SensorManager.SENSOR_DELAY_NORMAL)
        }

        escuchar(Sensor.TYPE_HEART_RATE, "frecuenciaCardiaca") { v -> if (v > 0f) v.toInt() else null }
        escuchar(Sensor.TYPE_STEP_COUNTER, "pasos") { total -> pasosDelDia(total.toLong()) }
        if (pendientes == 0) { terminar(); return }
        manejador.postDelayed({ terminar() }, 10_000)
    }

    /** El contador de pasos de Android acumula desde el último reinicio: se guarda la base del día para entregar «pasos de hoy». */
    private fun pasosDelDia(total: Long): Int {
        val prefs = getSharedPreferences("vitasync_pasos", Context.MODE_PRIVATE)
        val hoy = if (Build.VERSION.SDK_INT >= 26) LocalDate.now().toString() else java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date())
        var base = prefs.getLong("base", -1L)
        if (prefs.getString("dia", "") != hoy || base < 0 || total < base) { // día nuevo o reinicio del reloj
            base = total
            prefs.edit().putString("dia", hoy).putLong("base", base).apply()
        }
        return (total - base).toInt()
    }
}
