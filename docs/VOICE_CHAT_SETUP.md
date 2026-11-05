# Voz por proximidad: estado de integracion

`webrtc-native-1.2.1-stable` se ha revisado: es el **codigo fuente** de la
extension. No trae bibliotecas para Windows/Linux ni un archivo `.gdextension`
empaquetado dentro de `addons/`, por lo que Godot no debe cargarlo todavia.

## Lo que ya funciona en el proyecto

- El bus `Voice` captura el microfono sin reproducirlo localmente (evita eco).
- Ajustes persistentes para activar la voz, volumen de micrófono, Push-to-Talk y
  microfono abierto. La accion Push-to-Talk usa `V` por defecto y se puede
  reasignar desde Ajustes.
- HUD de estado de microfono y marcador `MIC` sobre un jugador remoto cuando el
  servidor recibe su estado de habla.
- `AudioStreamPlayer3D` para cada jugador remoto con atenuacion por distancia,
  radio de 26 metros y unidad de 4 metros.
- Senalizacion separada por Nakama Match Data (codigo `4100`) para ofertas,
  respuestas y candidatos ICE. No usa ni expone credenciales de base de datos.

## Preparar la extension nativa

Compila la extension una vez por plataforma desde la carpeta fuente:

```text
scons platform=windows target=release
scons platform=linux target=release
```

El propio proyecto de la extension genera el resultado bajo `bin/`. Copia la
carpeta generada por cada build al directorio raiz de Boomer Shooter, respetando
la estructura que entregue el build (normalmente `addons/webrtc_native/` con su
`.gdextension` y `lib/`). No copies solo `cfg.gdextension`: sin sus DLL/SO
correspondientes Godot fallara al iniciar.

Comprueba despues en Godot que la clase `WebRTCLibPeerConnection` aparece sin
errores. `VoiceManager` detecta esa clase en tiempo de ejecucion y no crea una
conexion WebRTC hasta que exista.

## Limite que hay que resolver antes de publicar voz real

Esta version de `webrtc-native` expone conexiones y `WebRTCDataChannel`, pero
no una pista de audio WebRTC/Opus utilizable desde GDScript. Por eso no se debe
enviar audio PCM crudo por Nakama: consume demasiado ancho de banda y genera
latencia. Para la voz audible final falta integrar un encoder Opus y un
reproductor con buffer de jitter, o adoptar un SDK de voz que ofrezca pistas de
audio nativas. La captura, UI, posicionamiento y senalizacion ya quedan aislados
para conectar ese transporte sin tocar la jugabilidad.
