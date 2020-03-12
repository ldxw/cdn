var address = (hasher.getURL()).replace((hasher.getBaseURL()), '');
var isEncode;
address = address.replace('#/', '');
if( address ) {
    $.get("actions.php", {
        action: 'encode'
    }).done(function (data) {
        isEncode = data;
        if(address.indexOf("@") != -1)    {
            createUser(address);
        } else {
            createUser(atob(address));
        }
    });
} else {
    $("#generateID").fadeIn(500);
    $.get("actions.php", {
        action: 'encode'
    }).done(function (data) {
        isEncode = data;
    });

}
var refreshRate;
$.get("actions.php", {
    action: 'refreshRate'
}).done(function( data ) {
    refreshRate = parseInt(data);
});
var pushNotifications;
$.get("actions.php", {
    action: 'pushNotifications'
}).done(function( data ) {
    if(data === 'yes') {
        pushNotifications = true;
    } else {
        pushNotifications = false;
    }
});
/*
* Notification Function
*/
function notifyUser(message) {
    if(pushNotifications) {
    	if (!("Notification" in window)) {
            document.getElementById('notifyUserSound').play();
        } else if (Notification.permission === "granted") {
            var notification = new Notification(message);
            document.getElementById('notifyUserSound').play();
        } else if (Notification.permission !== 'denied') {
            Notification.requestPermission(function(permission) {
                if (permission === "granted") {
                    var notification = new Notification(message);
                    document.getElementById('notifyUserSound').play();
                }
            });
        } else {
            document.getElementById('notifyUserSound').play();
        }
    } else {
        document.getElementById('notifyUserSound').play();
    }
}
/*
 *  Show About Us
 */
function showAboutUs() {
    $("#main").fadeOut( "slow", function() {
        $("#aboutus").fadeIn("slow");
    });
}
/*
 *  Close About Us
 */
function closeAboutUs() {
    $("#aboutus").fadeOut( "slow", function() {
        $("#main").fadeIn("slow");
    });
}
/*
 *  Set Language 
 */
function setLang() {
    var setLang = document.getElementsByName("lang")[0].value;
    $("#generateID").fadeOut(500);
    $("#createdline").fadeOut(500);
    $("#data").fadeOut(500);
    $("#search-bar-container").fadeOut(500);
    $(".message").fadeOut(500);
    if ( setLang === "hi" ) {
        $("#createline").html("डटे रहो! भाषा बदल रही है...");
    } else if ( setLang === "fr" ) {
        $("#createline").html("Attendre! Changer de langue...");
    } else if ( setLang === "ch" ) {
        $("#createline").html("不掛斷！改變語言...");
    } else if ( setLang === "ar" ) {
        $("#createline").html("تشبث! جار تغيير اللغة ...");
    } else if ( setLang === "sp" ) {
        $("#createline").html("¡Aférrate! Cambio de idioma...");
    } else if ( setLang === "ru" ) {
        $("#createline").html("Подожди! Изменение языка...");
    } else if ( setLang === "de" ) {
        $("#createline").html("Abwarten! Sprache ändern...");
    } else if ( setLang === "pl" ) {
        $("#createline").html("Wytrzymać! Zmiana języka...");
    } else {
        $("#createline").html("Hang on! Changing Language...");
    }
    $("#createline").delay(500).fadeIn(500);
    $.get( "actions.php", { action: "changeLang", lang: setLang } )
        .done(function( data ) {
            location.reload();
        });
}
/*
 * Set a New ID
 */
function setNewID() {
    $("#generateID").fadeOut(500);
    var email = document.getElementsByName("email")[0].value;
    var domain = document.getElementsByName("domain")[0].value;
    var fullEmail = email + domain;
    createUser(fullEmail);
}
/*
 * Generate a Random ID
 */
function generateRandomID() {
    $("#generateID").fadeOut(500);
    var address = (hasher.getURL()).replace((hasher.getBaseURL()), '');
    address = address.replace('#/', '');
    createUser(address);
}
/*
 * Create a new address for user. If address is already specified it checks if that is valid 
 */
function createUser(address) {
    $.get("actions.php", {
        action: 'getTitle'
    }).done(function( data ) {
        $("title").html(data);
    });
    $.get("user.php", {
        user: address
    }).done(function(data) {
        address = data;
        document.getElementById("address").innerHTML = address;
        if(isEncode === "yes") {
            var newAddress = btoa(address);
            hasher.setHash(newAddress);
        } else {
            hasher.setHash(address);
        }
        $("title").prepend(" - ");
        $("title").prepend(address);
        $("#createdline").delay(500).fadeIn(500);
        $.get("mail.php", function(data) {
            $("#data").html(data);
            $.get("actions.php", {
                action: 'getCount'
            }).done(function( data ) {
                counter = Number(data);
                if(counter > 1) {
                    $("#search-bar-container").delay(600).fadeIn(500);
                }
                $("#data").delay(600).fadeIn(500);
                $(".message").delay(600).fadeIn(500);
            });
            retriveNewMails();
        });
        classAddress = address.replace('@', '');
        classAddress = classAddress.replace('.', '');
        if (!$('.'+classAddress).length) {
            $(".action-list").append('<a class="'+classAddress+'" onclick="switchEmail(\''+address+'\')"><div class="action-list-button"><span class="action-info">'+address+'</span><i>'+classAddress.substring(1, 0, 1)+'</i></div></a>');
        }
        checkCurrentTMail();
    });
}
/* 
 * Switch Email ID
 */
function switchEmail(address) {
    $("#generateID").fadeOut(500);
    createUser(address);
}
/*
 * Function to check if element is empty with possible only blank spaces
 */
function isEmpty( el ){
    return !$.trim(el.html())
}
/*
 * Checks for new emails at regular interval. setTimeout calls function every 1000 ms (1 Second)
 */
function retriveNewMails() {
    str = $("title").text();
    counter = 0;
    if ( str.includes("nbox") ) {
        str = str.substring(str.indexOf("-") + 1);
    }
    $.get("actions.php", {
        action: 'getCount'
    }).done(function( data ) {
        $("title").text(str);
        counter = Number(data);
        if(counter > 1) {
            $("#search-bar-container").fadeIn(500);
        }
        $("title").prepend(" - ");
        $("title").prepend(")");
        $("title").prepend(data);
        $("title").prepend("Inbox (");
    });
    $.get("mail.php?unseen=1", function(data) {
        if (data.trim() === "DIE") {
            location.reload();
            return;
        }
        if(data) {
            if (!isEmpty($('.cssload-container'))) {
                $("#data").html(data);
            } else {
                $("#data").prepend(data);
            }   
            notifyUser("You got some new EMails");
        }
    });
    $("#timer").html(refreshRate);
    var acc = document.getElementsByClassName("accordion");
    var i;
    for (i = 0; i < acc.length; i++) {
        acc[i].onclick = function() {
            this.classList.toggle("active");
            var panel = this.nextElementSibling;
            if (panel.style.maxHeight){
              panel.style.maxHeight = null;
            } else {
              panel.style.maxHeight = panel.scrollHeight + "px";
            } 
        }
    }
    setTimeout(retriveNewMails, refreshRate*1000);
}
/*
 * Function to delete email
 * @param mailid - Identify the mail to delete
 */
function deleteMail(mailid) {
    $.get("actions.php", {
        action: 'delete',
        id: mailid
    });
    var mailLocator = "#mail".concat(mailid);
    $(mailLocator).hide( "slow", function() {
        $( this ).remove();
        if (isEmpty($('#data'))) {
            $("#data").html('<div class="cssload-container"><ul class="cssload-flex-container"><li><span class="cssload-loading"></span></li></div></div>');
        }
    });
    str = $("title").text();
    if ( str.includes("nbox") ) {
        str = str.substring(str.indexOf("-") + 1);
    }
    $.get("actions.php", {
        action: 'getCount'
    }).done(function( data ) {
        $("title").text(str);
        $("title").prepend(" - ");
        $("title").prepend(")");
        $("title").prepend(data);
        $("title").prepend("Inbox (");
    });
    return false;
}
/*
 * Function which enables user to download any email
 * @param mailid - Identify the mail to download
 */
function downloadMail(mailid) {
    $.get("actions.php", {
        action: 'download',
        id: mailid
    }).done(function( data ) {
        window.location.href = data;
    });
    return false;
}
/*
 * Simple click to copy to clipboard function
 */
function copyToClipboard(element) {
    var $temp = $("<input>");
    $("body").append($temp);
    $temp.val($(element).text()).select();
    document.execCommand("copy");
    $temp.remove();
}

$(document).ready(function(){
    $('[data-toggle="tooltip"]').tooltip();   
    $('[data-toggle="popover"]').popover({
        html : true
    }); 
    deleteAttachments();
});

$("#addDomain").click(function(){
    $("#addDomain").before('<input class="inner-fields" type="text" name="domain[]" placeholder="Enter Domain">');
});

$("#addForbidden").click(function(){
    $("#addForbidden").before('<input class="inner-fields" type="text" name="forbidemail[]" placeholder="Enter Forbiden EMail">');
});

$("#addLinks").click(function(){
    $("#addLinks").before('<input class="small-inner-fields" type="text" name="linksTitle[]" placeholder="Enter Title"><input class="big-inner-fields" type="text" name="linksValue[]" placeholder="Enter Link">');
});

/* 
 * Search Bar 
 */
 
(function(){
  var searchTerm, panelContainerId;
  $.expr[':'].containsCaseInsensitive = function (n, i, m) {
    return jQuery(n).text().toUpperCase().indexOf(m[3].toUpperCase()) >= 0;
  };
  
  $('#search-bar').on('change keyup paste click', function () {
    searchTerm = $(this).val();
    $('#data > .searchPanel').each(function () {
      panelContainerId = '#' + $(this).attr('id');
      $(panelContainerId + ':not(:containsCaseInsensitive(' + searchTerm + '))').hide();
      $(panelContainerId + ':containsCaseInsensitive(' + searchTerm + ')').show();
    });
  });
}());

/*
* Floating Action Bar 
*/

$( ".action-switch-email .action-button" ).mouseenter(function() {
	$( ".action-list" ).slideDown(200);
});
		
$( ".action-switch-email" ).mouseleave(function() {
	$( ".action-list" ).slideUp(200);
});
		
function setWidth() {
	$( ".action-list a" ).each(function( index ) {
		var string = $(this).children("div").children("span").text();
		var length = (string.length)*9;
		$(this).children("div").children("span").css("width",length+"px");
	});
}

/* 
* Function to check current TMail
*/

function checkCurrentTMail() {
    var address = (hasher.getURL()).replace((hasher.getBaseURL()), '');
    address = address.replace('#/', '');
    address = address.replace('@', '');
    address = address.replace('.', '');
    var classAddress = "."+address;
    $(".action-list a").show();
    $(classAddress).hide();
}
/*
* Check if enter key is pressed
*/
function checkEnter(e, item) {
    var code = (e.keyCode ? e.keyCode : e.which);
    if(code == 13) { 
        setNewID();
    }
}
/*
* Function for saving email in Cookie
*/
function saveEMails() {
    var xmlHttp = new XMLHttpRequest();
    xmlHttp.open( "GET", "actions.php?action=saveEMails", false );
    xmlHttp.send( null );
    if(xmlHttp.responseText == "1") {
        notifyUser("Email list stored successfully on your local machine.");
    } else {
        notifyUser("Fail to store emails list on your local machine. Please check if cookie is enabled in your browser.");
    }
}
/*
 * Function for clearing email in Cookie
 */
function clearEMails() {
    $.get("actions.php?action=clearEMails", function (data) {
        location.reload();
    });
}
/*
 * Deleting old attachments
 */
function deleteAttachments() {
    $.get("actions.php", {
        action: 'deleteOldAttachments'
    });
}

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