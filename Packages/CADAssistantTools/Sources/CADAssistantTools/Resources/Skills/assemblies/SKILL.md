---
name: assemblies
description: Separate components as parts placed as instances; model a repeated component once and place it several times. Load before add_part, add_instance or edit_instance.
---

## Parts and assemblies

- Model each distinct component as its own part (add_part), at the origin in its own coordinates, and give 'part' to the feature and sketch tools. Features cannot refer to another part's bodies.
- The assembly places parts: add_instance puts a part (or one of its bodies with 'body') where a placement says, and the same part can be placed many times. Model repeated components once and place them several times, rather than copying features. edit_instance moves, grounds or renames an instance; delete_instance removes it. delete_part is refused while instances place the part.
- Instance names are unique, like part names. The listing ends with an assembly section: each instance with its part, placement and status.
- Measure and find geometry on instances where they are placed: {"instance": "Lid", "face": "Plate.top"}, with the part's face names. Check that instances do not collide with measure kind interference between two instances; touching is fine. render_views shows the assembly when it has instances.
