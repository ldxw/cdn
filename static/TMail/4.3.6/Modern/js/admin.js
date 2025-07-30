//Admin JS

$("#addDomain").click(function(){
    $("#addDomain").before('<input class="inner-fields" type="text" name="domain[]" placeholder="Enter Domain">');
});

$("#addForbidden").click(function(){
    $("#addForbidden").before('<input class="inner-fields" type="text" name="forbidemail[]" placeholder="Enter Forbiden TMail">');
});

$("#addLinks").click(function(){
    $("#addLinks").before('<input class="small-inner-fields" type="text" name="linksIcon[]" placeholder="Enter Icon"><input class="small-inner-fields" type="text" name="linksTitle[]" placeholder="Enter Title"><input class="big-inner-fields" type="text" name="linksValue[]" placeholder="Enter Link">');
});

$("#test-connection").click(function(){
    $("#test-result").html("<span style='color: #006ECE'>Checking...</span>");
    var host = document.getElementsByName("host")[0].value;
    var user = document.getElementsByName("user")[0].value;
    var pass = document.getElementsByName("pass")[0].value;
    $.get("admin.php", {
        host: host,
        user: user,
        pass: pass
    }).done(function( data ) {
        if(data === 'FAIL') {
            $("#test-result").html("<span style='color: #DB0015'>Connection Failed</span>");
        } else {
            $("#test-result").html("<span style='color: #006e2e'>Connection Passed</span>");
        }
    });
});