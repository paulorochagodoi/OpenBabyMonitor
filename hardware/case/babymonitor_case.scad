// ============================================================================
// OpenBabyMonitor - parametric 3D-printed enclosure for the Raspberry Pi 4B
// plus the white-noise speaker and the night-light LED ring.
//
// This is a PARAMETRIC STARTING POINT, not a guaranteed drop-in fit. The
// Raspberry Pi 4B port positions and component sizes below are taken from the
// published mechanical data and common module sizes, but you MUST verify them
// against your own boards / the official mechanical drawing and tweak the
// variables in the "PARAMETERS" block before printing. Print a quick test of
// the port wall first.
//
// Render / export (headless):
//   openscad -D 'part="base"' -o babymonitor_case_base.stl babymonitor_case.scad
//   openscad -D 'part="lid"'  -o babymonitor_case_lid.stl  babymonitor_case.scad
//
// Set part="both" (default) in the GUI to preview the assembly.
// ============================================================================

part = "both";   // "base", "lid" or "both"
$fn = 72;

// ----------------------------------------------------------------------------
// PARAMETERS
// ----------------------------------------------------------------------------

// --- Raspberry Pi 4B board ---
pi_l   = 85;     // board length (X)
pi_w   = 56;     // board width  (Y)
pcb_th = 1.5;    // PCB thickness

hole_inset = 3.5;   // mounting-hole centre inset from board edges
hole_dx    = 58;    // mounting-hole spacing along X
hole_dy    = 49;    // mounting-hole spacing along Y

// --- Mounting standoffs ---
standoff_od = 6;
standoff_h  = 5;
screw_d     = 2.6;   // M2.5 self-tapping into the standoff

// --- Enclosure shell ---
wall      = 2.5;
floor_th  = 2.5;
top_th    = 2.0;
gap       = 1.5;     // clearance between board edge and inner wall
corner_r  = 4;

port_zone_h = 16;    // height of the port openings above the PCB top
top_clear   = 8;     // solid wall band above the ports (lid clearance)

// --- Lid (holds the speaker and the LED ring) ---
lid_h     = 24;      // internal height of the lid cavity
skirt_h   = 7;       // how far the lid skirt overlaps the base outside
skirt_th  = 2.2;     // lid skirt wall thickness
fit_gap   = 0.4;     // slip-fit clearance between lid skirt and base
diffuser_th = 1.2;   // thin membrane over the LED ring (print lid in white PLA)

// --- White-noise speaker (round, top-firing through a grille) ---
spk_d           = 38;   // speaker diameter
spk_seat_th     = 1.8;  // retaining-ring wall thickness
spk_ring_h      = 6;    // retaining-ring depth
spk_grille_hole = 2.5;  // grille hole diameter
spk_grille_gap  = 4;    // grille hole pitch

// --- Night-light WS2812 / NeoPixel ring ---
ring_od     = 52;   // ring outer diameter  (VERIFY against your ring)
ring_id     = 44;   // ring inner diameter
ring_seat_h = 3;    // depth of the seat that holds the ring

// --- Camera (Raspberry Pi Camera Module v2 / NoIR), on the -X short wall ---
cam_enabled  = true;
cam_lens_d   = 8;
cam_hole_dx  = 21;    // camera mounting-hole spacing (horizontal)
cam_hole_dy  = 12.5;  // camera mounting-hole spacing (vertical)
cam_screw_d  = 2.0;   // M2

// --- Tripod mount (1/4"-20) on the base underside ---
tripod_enabled = true;
tripod_bolt_d  = 6.5;   // 1/4" clearance
tripod_nut_af  = 11.6;  // 1/4"-20 hex nut across-flats + clearance
tripod_nut_th  = 6;

// --- Ventilation ---
vent_slot_w   = 3;
vent_slot_len = 22;

// ----------------------------------------------------------------------------
// DERIVED DIMENSIONS
// ----------------------------------------------------------------------------
in_l  = pi_l + 2*gap;             // interior length
in_w  = pi_w + 2*gap;             // interior width
out_l = in_l + 2*wall;            // outer length
out_w = in_w + 2*wall;            // outer width

pcb_bottom_z = floor_th + standoff_h;
pcb_top_z    = pcb_bottom_z + pcb_th;
base_h       = pcb_top_z + port_zone_h + top_clear;   // total base height

board_x0 = wall + gap;            // board origin (interior corner)
board_y0 = wall + gap;

port_z0  = pcb_top_z - 1;         // bottom of the port openings

cx = out_l/2;                     // top-feature centre
cy = out_w/2;

post_inset = wall + 3;            // corner screw-post centre inset

// Pi 4B port centres, measured from the board corner near the USB-C end.
// VERIFY THESE before printing.
usbc_x  = 11.2;   // along the long edge (faces -Y)
hdmi0_x = 26.0;
hdmi1_x = 39.5;
audio_x = 54.0;
eth_y   = 10.25;  // along the short edge (faces +X)
usb1_y  = 27.0;   // USB3 pair
usb2_y  = 45.75;  // USB2 pair

// ----------------------------------------------------------------------------
// HELPERS
// ----------------------------------------------------------------------------

// Rounded-corner box (rounded vertical edges), origin at the min corner.
module rbox(l, w, h, r) {
  hull() for (x = [r, l - r], y = [r, w - r])
    translate([x, y, 0]) cylinder(h = h, r = r);
}

// Hollow tube (annular cylinder) centred on the origin.
module tube(od, id, h) {
  difference() {
    cylinder(h = h, d = od);
    translate([0, 0, -0.1]) cylinder(h = h + 0.2, d = id);
  }
}

// Place children at the four corner screw-post positions.
module post_positions() {
  for (px = [post_inset, out_l - post_inset], py = [post_inset, out_w - post_inset])
    translate([px, py, 0]) children();
}

// Port opening through the -Y long wall at X position cx_.
module port_y(cx_, opening_w, opening_h) {
  translate([board_x0 + cx_ - opening_w/2, -1, port_z0])
    cube([opening_w, wall + gap + 2, opening_h]);
}

// Port opening through the +X short wall at Y position cy_.
module port_x(cy_, opening_w, opening_h) {
  translate([out_l - wall - gap - 1, board_y0 + cy_ - opening_w/2, port_z0])
    cube([wall + gap + 2, opening_w, opening_h]);
}

// ----------------------------------------------------------------------------
// BASE
// ----------------------------------------------------------------------------

module standoffs() {
  for (dx = [0, hole_dx], dy = [0, hole_dy])
    translate([board_x0 + hole_inset + dx, board_y0 + hole_inset + dy, floor_th])
      difference() {
        cylinder(h = standoff_h, d = standoff_od);
        translate([0, 0, -0.1]) cylinder(h = standoff_h + 0.2, d = screw_d);
      }
}

module lid_posts() {
  post_positions()
    translate([0, 0, floor_th])
      difference() {
        cylinder(h = base_h - floor_th, d = 7);
        translate([0, 0, base_h - floor_th - 9]) cylinder(h = 9.2, d = screw_d);
      }
}

module floor_vents() {
  for (i = [-2 : 2])
    translate([cx - vent_slot_w/2, cy - vent_slot_len/2 + i*6, -1])
      hull() {
        cube([vent_slot_w, 0.01, floor_th + 2]);
        translate([0, vent_slot_len, 0]) cube([vent_slot_w, 0.01, floor_th + 2]);
      }
}

module side_vents() {
  n = 6;
  spacing = (in_l - vent_slot_w) / (n - 1);
  for (i = [0 : n - 1])
    translate([board_x0 + i*spacing, out_w - wall - 1, floor_th + 4])
      cube([vent_slot_w, wall + 2, base_h - floor_th - 12]);
}

module tripod_mount() {
  if (tripod_enabled)
    translate([cx, cy, -1]) {
      cylinder(h = floor_th + 2, d = tripod_bolt_d);
      cylinder(h = tripod_nut_th + 1, d = tripod_nut_af / cos(30), $fn = 6);
    }
}

module camera_cutout() {
  if (cam_enabled)
    translate([-1, cy, pcb_top_z + 9]) rotate([0, 90, 0]) {
      cylinder(h = wall + gap + 2, d = cam_lens_d);
      for (sx = [-cam_hole_dx/2, cam_hole_dx/2], sy = [-cam_hole_dy/2, cam_hole_dy/2])
        translate([sy, sx, 0]) cylinder(h = wall + 2, d = cam_screw_d);
    }
}

module base() {
  difference() {
    rbox(out_l, out_w, base_h, corner_r);                  // outer shell
    translate([wall, wall, floor_th])
      rbox(in_l, in_w, base_h, max(corner_r - wall, 0.5)); // interior cavity
    port_y(usbc_x,  12, 9);
    port_y(hdmi0_x, 9,  7);
    port_y(hdmi1_x, 9,  7);
    port_y(audio_x, 8,  8);
    port_x(eth_y,   18, port_zone_h);
    port_x(usb1_y,  16, port_zone_h);
    port_x(usb2_y,  16, port_zone_h);
    floor_vents();
    side_vents();
    tripod_mount();
    camera_cutout();
  }
  standoffs();
  lid_posts();
}

// ----------------------------------------------------------------------------
// LID
// ----------------------------------------------------------------------------

module speaker_grille() {
  steps = floor(spk_d / spk_grille_gap);
  for (i = [-steps : steps], j = [-steps : steps]) {
    gx = i * spk_grille_gap + (j % 2) * spk_grille_gap/2;
    gy = j * spk_grille_gap * 0.87;
    if (sqrt(gx*gx + gy*gy) < spk_d/2 - spk_grille_hole)
      translate([cx + gx, cy + gy, -1])
        cylinder(h = top_th + 2, d = spk_grille_hole);
  }
}

module lid() {
  difference() {
    union() {
      rbox(out_l, out_w, top_th, corner_r);                // top plate
      // outer skirt that wraps over the base for a clean, light-tight fit
      translate([-skirt_th + (out_l - (out_l + 2*fit_gap + 2*skirt_th))/2,
                 -skirt_th + (out_w - (out_w + 2*fit_gap + 2*skirt_th))/2, -skirt_h])
        difference() {
          rbox(out_l + 2*fit_gap + 2*skirt_th, out_w + 2*fit_gap + 2*skirt_th, skirt_h, corner_r + skirt_th);
          translate([skirt_th, skirt_th, -0.1])
            rbox(out_l + 2*fit_gap, out_w + 2*fit_gap, skirt_h + 0.2, corner_r);
        }
      // speaker retaining ring (underside)
      translate([cx, cy, -spk_ring_h]) tube(spk_d + 2*spk_seat_th, spk_d, spk_ring_h);
      // LED ring seat (underside): outer + inner retaining walls
      translate([cx, cy, -ring_seat_h]) tube(ring_od + 2*skirt_th, ring_od, ring_seat_h);
      translate([cx, cy, -ring_seat_h]) tube(ring_id, ring_id - 2*skirt_th, ring_seat_h);
    }
    // grille holes over the speaker
    speaker_grille();
    // LED ring diffuser window: thin the top plate over the ring annulus
    translate([cx, cy, diffuser_th]) tube(ring_od, ring_id, top_th);
    // lid screw clearance holes aligning to the base posts
    post_positions() translate([0, 0, -1]) cylinder(h = top_th + 2, d = 3.2);
  }
}

// ----------------------------------------------------------------------------
// RENDER
// ----------------------------------------------------------------------------
if (part == "base")
  base();
else if (part == "lid")
  translate([0, out_w, top_th]) rotate([180, 0, 0]) lid();   // print upside down
else {
  base();
  translate([0, 0, base_h + lid_h + 12]) color("LightBlue") lid();
}
