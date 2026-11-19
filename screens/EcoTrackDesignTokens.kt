package com.ecotrack.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.shape.RoundedCornerShape

/**
 * EcoTrack Design Tokens (извлечено напрямую из прототипов Figma / prot.svg)
 * Лабораторная работа №5: CustDev и UX-проектирование
 */
object EcoTrackTokens {
    // 1. Цветовая палитра (Wireframe Grayscale)
    val BackgroundScreen = Color(0xFFFFFFFF)
    val BackgroundCanvas = Color(0xFF1E1E1E)
    val SurfaceCard = Color(0xFFD9D9D9)
    val SurfaceCardSubtle = Color(0xFFECECEC)
    val SurfaceElement = Color(0xFFB0B0B0)
    val SurfaceAccent = Color(0xFFC4C4C4)
    val SurfaceActive = Color(0xFF868686)
    val TextPrimary = Color(0xFF1E1E1E)
    val TextSecondary = Color(0xFF5A5A5A)
    val TextMuted = Color(0xFF8C8C8C)

    // 2. Сетки и отступы (Layout Spacing)
    val ScreenWidth = 412.dp
    val ScreenHeight = 917.dp
    val HorizontalPadding = 22.dp  // Базовый горизонтальный отступ экрана
    val CardGap = 18.dp            // Расстояние между карточками активности
    val CardWidth = 368.dp         // Ширина стандартной карточки (412 - 22 * 2)
    val CardHeight = 107.dp        // Высота карточки активности / экономии

    // 3. Формы и скругления (Corner Shapes)
    val ShapeCard = RoundedCornerShape(20.dp)       // Карточки активности
    val ShapePill = RoundedCornerShape(27.dp)       // Нижняя навигация и теги
    val ShapeButton = RoundedCornerShape(25.dp)     // Кнопки быстрого действия
    val ShapeBadge = RoundedCornerShape(28.5.dp)    // Баланс эко-баллов в шапке
    val ShapeTag = RoundedCornerShape(17.5.dp)      // Маленькие переключатели

    // 4. Компоненты навигации
    val BottomNavWidth = 322.dp
    val BottomNavHeight = 54.dp
    val BottomNavPaddingBottom = 27.dp
}
