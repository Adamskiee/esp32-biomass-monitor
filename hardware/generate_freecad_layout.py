import FreeCAD as App
import Part

def create_block(doc, name, length, width, height, x, y, z, color=(0.5, 0.5, 0.5)):
    box = Part.makeBox(length, width, height)
    box.translate(App.Vector(x, y, z))
    obj = doc.addObject("Part::Feature", name)
    obj.Shape = box
    obj.ViewObject.ShapeColor = color
    return obj

def create_cylinder(doc, name, radius, height, x, y, z, rotation_axis, angle, color=(0.2, 0.2, 0.2)):
    cyl = Part.makeCylinder(radius, height)
    if angle != 0:
        cyl.rotate(App.Vector(0,0,0), App.Vector(*rotation_axis), angle)
    cyl.translate(App.Vector(x, y, z))
    obj = doc.addObject("Part::Feature", name)
    obj.Shape = cyl
    obj.ViewObject.ShapeColor = color
    return obj

def generate_biomass_prototype():
    doc = App.newDocument("BiomassPrototype")
    
    # Base Dimensions
    chamber_l, chamber_w, chamber_h = 400, 400, 400
    filter_l, filter_w, filter_h = 300, 400, 400
    
    # 1. Burning Chamber (Red-ish)
    chamber = create_block(doc, "BurningChamber", chamber_l, chamber_w, chamber_h, 0, 0, 0, color=(0.8, 0.2, 0.2))
    chamber.ViewObject.Transparency = 50
    
    # 2. Pressure-Relief Chimney (Grey) - offset to prevent sprinkler collision
    create_cylinder(doc, "PressureReliefChimney", 40, 200, chamber_l/4, chamber_w/4, chamber_h, (1,0,0), 0)
    
    # 2b. Thermocouple (inside chamber)
    create_cylinder(doc, "Thermocouple", 5, 100, chamber_l/2, 50, chamber_h - 100, (1,0,0), 0, color=(0.9, 0.9, 0.9))
    
    # 3. Exhaust Pipe & Damper (Black)
    create_cylinder(doc, "VentilationPipe", 60, 200, chamber_l, chamber_w/2, chamber_h - 100, (0,1,0), 90, color=(0.1, 0.1, 0.1))
    create_block(doc, "SpringReturnDamper", 20, 150, 150, chamber_l + 90, chamber_w/2 - 75, chamber_h - 175, color=(0.3, 0.3, 0.3))
    
    # 4. Multi-stage Filtration Frame (Blue-ish)
    create_block(doc, "FiltrationFrame", filter_l, filter_w, filter_h, chamber_l + 200, 0, 0, color=(0.2, 0.4, 0.8))
    
    # MQ Sensors embedded at the end of the filtration frame
    # Protruding slightly from the top so they are visually clear in FreeCAD
    create_block(doc, "MQSensors", 50, 100, 50, chamber_l + 200 + filter_l - 50, 150, filter_h - 25, color=(0.2, 0.8, 0.2))

    # Align fan with exhaust pipe center (pipe Z=300, fan height 300, so Z=150)
    create_block(doc, "ExhaustVent", 100, 300, 300, chamber_l + 200 + filter_l, 50, 150, color=(0.1, 0.1, 0.1))
    create_block(doc, "MoistureTrap", 80, 80, 150, chamber_l + 200 + filter_l + 100, 160, 225, color=(0.6, 0.6, 0.6))
    
    # Final Exhaust Chimney directing clean air up
    create_cylinder(doc, "OutputChimney", 40, 300, chamber_l + 200 + filter_l + 140, 200, 375, (1,0,0), 0, color=(0.3, 0.3, 0.3))
    
    # 5. Overhead Water Rack & Container (Offset Laterally)
    # Rack offset by 100mm on Y axis to prevent direct plume heat
    rack_z = chamber_h + 300
    rack_y = chamber_w + 100 
    rack = create_block(doc, "StructuralWaterRack", 320, 320, rack_z, 40, rack_y - 10, 0, color=(0.4, 0.4, 0.4))
    rack.ViewObject.Transparency = 50
    create_block(doc, "ThermalShield", chamber_l, 10, 300, 0, chamber_w + 10, chamber_h + 30, color=(0.9, 0.9, 0.9)) # Gap for pipe
    create_block(doc, "WaterContainer", 300, 300, 400, 50, rack_y, rack_z, color=(0.1, 0.4, 0.9))
    
    # 6. Safety Pipe Routing, Solenoid, & Interlock
    # Drop down from container (Ends flush with horizontal pipe at chamber_h + 15)
    create_cylinder(doc, "WaterPipeDrop", 15, rack_z - (chamber_h + 15), 200, rack_y + 150, chamber_h + 15, (1,0,0), 0)
    # Horizontal run to chamber center (Sits on top of chamber)
    create_cylinder(doc, "WaterPipeHorizontal", 15, rack_y + 150 - (chamber_w/2), 200, chamber_w/2, chamber_h + 15, (1,0,0), -90)
    # Sprinkler inside chamber (Drops from horizontal pipe into chamber)
    create_cylinder(doc, "MistingSprinkler", 30, 55, 200, chamber_w/2, chamber_h - 40, (1,0,0), 0, color=(0.8, 0.8, 0.8))
    
    create_block(doc, "ManualBallValve_LimitSwitch", 50, 50, 50, 175, rack_y + 125, rack_z - 100, color=(0.8, 0.8, 0.1))
    create_block(doc, "DirectActing_NO_Solenoid", 60, 60, 60, 170, rack_y + 120, rack_z - 200, color=(0.9, 0.1, 0.1))
    
    # 7. Electronics Enclosure (Segregated away from water)
    create_block(doc, "ESP32_Microcontroller_Box", 200, 100, 300, chamber_l + 200 + filter_l + 200, 0, 0, color=(0.8, 0.8, 0.8))
    create_cylinder(doc, "HardwareEStop", 30, 20, chamber_l + 200 + filter_l + 250, -20, 200, (1,0,0), -90, color=(0.9, 0.1, 0.1))
    create_block(doc, "LED_Light_Indicator", 30, 10, 30, chamber_l + 200 + filter_l + 250, -10, 100, color=(0.1, 0.9, 0.1))
    create_cylinder(doc, "Buzzer_Alarm", 15, 10, chamber_l + 200 + filter_l + 270, -10, 60, (1,0,0), -90, color=(0.2, 0.2, 0.2))
    
    App.ActiveDocument.recompute()
    print("Biomass Prototype layout generated successfully.")

if __name__ == '__main__':
    generate_biomass_prototype()
