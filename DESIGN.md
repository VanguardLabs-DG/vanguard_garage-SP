---
version: alpha
name: Vanguard Garage Admin Panel
description: Dynamic garage management panel for vanguard_garage, integrated as an mri_Qadmin plugin, matching CallAdmin visual language and UX.
colors:
  canvas: "#070b12"
  surface: "#0c121d"
  surface-raised: "#111a28"
  surface-soft: "#151f2e"
  surface-hover: "#192537"
  border: "rgba(148, 163, 184, 0.13)"
  border-strong: "rgba(148, 163, 184, 0.22)"
  text: "#f4f7fb"
  text-muted: "#8f9bad"
  text-faint: "#64748b"
  primary: "#43d38b"
  primary-strong: "#22b873"
  primary-soft: "rgba(67, 211, 139, 0.12)"
  blue: "#5aa9ff"
  yellow: "#f7c96b"
  danger: "#ff6b7a"
  danger-soft: "rgba(255, 107, 122, 0.12)"
typography:
  font-family: 'Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'
  heading-lg:
    fontSize: "20px"
    fontWeight: 700
    lineHeight: 1.2
  body-md:
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  badge-sm:
    fontSize: "11px"
    fontWeight: 600
    lineHeight: 1.2
rounded:
  sm: "8px"
  md: "12px"
  lg: "18px"
  full: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
---

# Vanguard Garage Admin Panel (Qadmin Plugin)

## Overview
This design specification defines the visual tokens and interface patterns for the dynamic garage management administration interface of `vanguard_garage`, hosted inside an iframe within `mri_Qadmin`.

## Visual Identity & Alignment
- Retains 100% fidelity to the CallAdmin city module aesthetics: dark futuristic theme with jade-emerald accents (`#43d38b`).
- Card-based layouts, glassmorphism borders (`rgba(148, 163, 184, 0.13)`), high-contrast data tables, interactive coordinates capture buttons with status indicators, and modal workflows.

## Components
- **Header Toolbar**: Search input, reload button, "Nova garagem" action button.
- **Data Table**: Displays garage list with columns (ID, ID Externo, Tipo/Lista de Veículos, Permissão, Pagamento, Vagas de Spawn, Ações).
- **Edit/Create Modal**: Form with garageId input, vehicle type combobox (sourced from `vanguard_garage` works/presets), permission input, payment toggle switch, and interactive spawn slot manager.
- **In-Game World Object Capture**: Floating status display with live marker drawing and ENTER/ESC binding.
