local locale = GetLocale()
if locale ~= "esES" and locale ~= "esMX" then return end

Interruptio = Interruptio or {}
Interruptio.L = Interruptio.L or {}
local L = Interruptio.L

-- =========================================================
-- SPANISH (esES / esMX)
-- =========================================================

-- UI Headers
L["PANEL_HEADER"] = "INTERRUPTIO"
L["READY"] = "READY"
L["CD_REMAINING"] = " - cd %s s"
L["READY_SUFFIX"] = " - READY"

-- Settings Categories
L["CAT_GENERAL"] = "General"
L["CAT_PANEL"] = "Panel Flotante"
L["CAT_NAMEPLATES"] = "Placas de Nombre"

-- General Settings
L["OPT_SCALE"] = "Escala General"
L["OPT_SCALE_DESC"] = "Ajusta el tamaño global de la interfaz."
L["OPT_ANNOUNCE"] = "Anunciar asignaciones en grupo"
L["OPT_ANNOUNCE_DESC"] = "Enviar mensaje al chat de grupo /p cada vez que cambias tu marca."
L["OPT_ANNOUNCE_CD"] = "Anunciar tu CD al marcar"
L["OPT_ANNOUNCE_CD_DESC"] = "Añade el tiempo de recarga (CD) que le queda a tu corte en el mensaje de chat al asignar una marca."
L["OPT_AUTO_FOCUS"] = "Añadir Foco (Automático)"
L["OPT_AUTO_FOCUS_DESC"] = "Elige cómo quieres que se ponga automáticamente en foco al enemigo al que le asignas tu marca."
L["VAL_NONE"] = "Desactivado"
L["VAL_TARGET"] = "Objetivo Actual"
L["VAL_MOUSEOVER"] = "Mouseover (Bajo el ratón)"
L["OPT_DEBUG"] = "Logs de Debug"
L["OPT_DEBUG_DESC"] = "Muestra mensajes de depuración en el chat."

-- Panel Settings
L["OPT_MODERN"] = "UI Moderna (Translúcida & Fluida)"
L["OPT_MODERN_DESC"] = "Activa fondos estilo 'cristal' translúcidos y barras con movimiento y destellos brillantes suaves."
L["OPT_EMPHASIZE"] = "Resaltar Disp. (Atenuación + Latido)"
L["OPT_EMPHASIZE_DESC"] = "Las barras de cortes en enfriamiento se oscurecen al 60% y sus iconos se vuelven grises. Los disponibles laten al 100%."
L["OPT_CLASS_BARS"] = "Barras Progreso Clásicas (Color Clase)"
L["OPT_CLASS_BARS_DESC"] = "Las barras de enfriamiento rellenarán toda su altura con el color de clase estilo clásico, sustituyendo la línea de color dinámico."
L["OPT_HIDE_PANEL"] = "Ocultar Panel Flotante"
L["OPT_HIDE_PANEL_DESC"] = "Oculta el panel flotante de lista, dejando activos solo los iconos en las placas de nombre."
L["OPT_HIDE_FRAME"] = "Fondo Transparente (Ocultar Marco)"
L["OPT_HIDE_FRAME_DESC"] = "Oculta por completo el fondo y los bordes del panel, dejando que las barras floten libremente sin marco."
L["OPT_VISIBILITY_MODE"] = "Visibilidad del Panel"
L["OPT_VISIBILITY_MODE_DESC"] = "Elige en qué situaciones se mostrará el panel flotante automáticamente."
L["VAL_VISIBILITY_ALWAYS"] = "Siempre (Aventuras, Mundo, etc.)"
L["VAL_VISIBILITY_DUNGEON"] = "Solo en Mazmorras (Grupos)"
L["VAL_VISIBILITY_RAID"] = "Solo en Bandas (Raid)"
L["VAL_VISIBILITY_DUNGEON_RAID"] = "Mazmorra y Banda"
L["OPT_BAR_TEXTURE"] = "Textura de las Barras"
L["OPT_BAR_TEXTURE_DESC"] = "Elige la textura de las barras. Detectará automáticamente opciones de Addons como ElvUI/Plater gracias a LibSharedMedia."
L["OPT_SPELL_ICON"] = "Mostrar Icono del Hechizo"
L["OPT_SPELL_ICON_DESC"] = "Muestra el icono del hechizo de interrupción a la izquierda del nombre del jugador."
L["BTN_TEST_MODE"] = "Generar Grupo Prueba"
L["BTN_TEST_MODE_DESC"] = "Genera un grupo falso con cortes ficticios para probar el panel."
L["BTN_UNLOCK"] = "Desbloquear Panel"
L["BTN_UNLOCK_DESC"] = "Muestra un fondo visible en el panel flotante para que puedas arrastrarlo y posicionarlo fácilmente."
L["UNLOCK_DRAG_ME"] = "ARRÁSTRAME"

-- Nameplate Settings
L["OPT_NP_GLOW"] = "Brillo en Nameplate Asignada"
L["OPT_NP_GLOW_DESC"] = "Muestra un borde brillante alrededor de la barra de vida del mob al que tienes que cortar."
L["OPT_NP_FRONT"] = "Traer barra al Frente (Top Layer)"
L["OPT_NP_FRONT_DESC"] = "Fuerza a la barra de vida de tu objetivo asignado a renderizarse por encima del resto."
L["OPT_NP_SCALE"] = "Tamaño de la Barra del Objetivo"
L["OPT_NP_SCALE_DESC"] = "Multiplicador de tamaño de la barra de vida del mob asignado."
L["OPT_ICON_SIDE"] = "Lado de los iconos de corte"
L["OPT_ICON_SIDE_DESC"] = "Punto de anclaje de los iconos respecto a la barra de vida (Izquierda, Derecha, Arriba, Abajo)."
L["OPT_ICON_H_OFFSET"] = "Separación horizontal de iconos"
L["OPT_ICON_H_OFFSET_DESC"] = "Distancia horizontal de los iconos desde el borde de la barra de vida."
L["OPT_ICON_V_OFFSET"] = "Alineación vertical de iconos"
L["OPT_ICON_V_OFFSET_DESC"] = "Alineación vertical de los iconos si quieres desplazarlos arriba o abajo del centro."
L["VAL_LEFT"] = "Izquierda"
L["VAL_RIGHT"] = "Derecha"
L["VAL_TOP"] = "Arriba"
L["VAL_BOTTOM"] = "Abajo"

-- Chat Messages
L["MSG_ASSIGNED_PARTY"] = "Corte de %s asignado a %s"
L["MSG_ASSIGNED_SELF"] = "[Interruptio] Asignado a %s (%s)"

-- Keybindings
_G["BINDING_HEADER_INTERRUPTIO"] = "Interruptio"
_G["BINDING_NAME_CLICK InterruptioMarkSABT:LeftButton"] = "Asignar / Quitar Marca de Corte"
