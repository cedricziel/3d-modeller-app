---
name: sketches
description: Profiles a primitive cannot make, such as L or T sections, slots, plates with cut-outs and turned parts: constrained sketches, extrude and revolve. Load before add_sketch, edit_sketch, or adding an extrude or revolve.
---

## Sketches

- Use a sketch for any profile a primitive cannot make: L or T sections, slots, plates with cut-outs, turned parts. add_sketch takes the whole sketch in one call; edit_sketch changes it; get_sketch shows it.
- Planes: XY (x = X, y = Y, normal +Z), XZ (x = X, y = Z, normal -Y), YZ (x = Y, y = Z, normal +X), or a planar face such as Box1.top with 'body' (normal out of the body). 'offset' moves the plane along its normal.
- Entities: line {start, end}, arc {center, radius, startAngle, endAngle} (degrees, counter-clockwise), circle {center, radius}, point {at}; construction: true for helper geometry. They are named line1, arc1, circle1, point1… Points are line1.start, line1.end, arc1.start, arc1.end, arc1.center, circle1.center.
- Draw the entities close to their final positions: the coordinates are only the solver's starting guess.
- Constrain the sketch fully, so the result says fully constrained: join every corner with coincident, make lines horizontal or vertical where they are, dimension every length and radius (use parameters for the ones the user may change), and fix one point with fixed at [x, y] to place the sketch. Each point has two degrees of freedom, a line four, a circle three and an arc five; an under-constrained result says how many are left. For a line joining an arc smoothly use tangentAt on the shared end points, not coincident plus tangent. Over-constrained sketches fail and name the conflicting constraints; remove one of them.
- Closed loops of non-construction entities are the regions; a loop inside another is a hole. extrude sweeps regions along the plane normal (distance, symmetric, throughAll, upToFace; reversed flips it); revolve turns them about a sketch line, X, Y or Z. Both take an operation like solids. To cut into a face you sketched on, extrude with reversed: true or extent throughAll.
- Faces made from a sketch are named after the entity: Extrude1.side[Sketch1.line3], and the caps Extrude1.start and Extrude1.end. start is on the sketch plane for distance and upToFace; for symmetric and throughAll it is the cap behind the plane, against its normal.
