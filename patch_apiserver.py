import re

with open('firmware/main/ApiServer.cpp', 'r') as f:
    content = f.read()

# Issue 5: setMethod(HTTP_POST)
content = content.replace('server.addHandler(controlHandler);', 'controlHandler->setMethod(HTTP_POST);\n    server.addHandler(controlHandler);')
content = content.replace('server.addHandler(thresholdHandler);', 'thresholdHandler->setMethod(HTTP_POST);\n    server.addHandler(thresholdHandler);')

# Issue 2: thresholdHandler state_needs_save logic
old_logic = """        if (jsonObj.containsKey("safe_chamber_limit")) {
            float val = jsonObj["safe_chamber_limit"];
            if (val >= 0 && val <= 1000) threshold_chamber_temp_c = val;
        }
        if (jsonObj.containsKey("safe_mq2_limit")) {
            float val = jsonObj["safe_mq2_limit"];
            if (val >= 0 && val <= 5.0) threshold_mq2_v = val;
        }
        state_needs_save = true;"""

new_logic = """        bool changed = false;
        if (jsonObj.containsKey("safe_chamber_limit")) {
            float val = jsonObj["safe_chamber_limit"];
            if (val >= 0 && val <= 1000 && threshold_chamber_temp_c != val) {
                threshold_chamber_temp_c = val;
                changed = true;
            }
        }
        if (jsonObj.containsKey("safe_mq2_limit")) {
            float val = jsonObj["safe_mq2_limit"];
            if (val >= 0 && val <= 5.0 && threshold_mq2_v != val) {
                threshold_mq2_v = val;
                changed = true;
            }
        }
        if (changed) state_needs_save = true;"""

content = content.replace(old_logic, new_logic)

with open('firmware/main/ApiServer.cpp', 'w') as f:
    f.write(content)
