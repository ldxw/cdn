$(document).ready(function () {
    $('[data-toggle="tooltip"]').tooltip();
    deleteAttachments();
});

const scrollHome = new PerfectScrollbar('.tmail-homepage');
const scrollSidebar = new PerfectScrollbar('.tmail-sidebar');
const scrollTmailList = new PerfectScrollbar('.tmail-list');
const scrollTmailBody = new PerfectScrollbar('.tmail-email-body');
const scrollTmailListSection = new PerfectScrollbar('#tmail-switcher-list-ul');

var isEncode;
var address = (hasher.getURL()).replace((hasher.getBaseURL()), '');
address = address.replace('#/', '');
if (address) {
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
    $(".tmail-loader").fadeOut(200, function(){
        $(".tmail-main-inner").delay(400).fadeIn();
        scrollHome.update();
        $.get("actions.php", {
            action: 'encode'
        }).done(function (data) {
            isEncode = data;
        });
    });
}

var refreshRate;
$.get("actions.php", {
    action: 'refreshRate'
}).done(function (data) {
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

var t;
var currentRefreshRate;
var intialText = $("#reloading-line").html();

function updateTimer() {
    if(currentRefreshRate == refreshRate) {
        $("#reloading-line").fadeOut(200, function(){
            $("#reloading-line").html(intialText);
        });
    }
    $("#reloading-msg").html("<strong>"+(currentRefreshRate)+"</strong>");
    if(currentRefreshRate == refreshRate) {
        $("#reloading-line").fadeIn(200);
    } 
    if(currentRefreshRate == 0) {
        retriveNewMails();
        clearInterval(t);
        $("#reloading-line").fadeOut(200, function(){
            $("#reloading-line").html('<i class="fa fa-spinner fa-spin" aria-hidden="true"></i>');
            $("#reloading-line").delay(100).fadeIn(200);
        });
        
    }
    currentRefreshRate = currentRefreshRate - 1;
}

/*
 * Check if enter key is pressed
 */
function checkEnter(e, item) {
    var code = (e.keyCode ? e.keyCode : e.which);
    if (code === 13) {
        setNewID();
    }
}
/*
 * Set a New ID
 */
function setNewID() {
    var email = document.getElementsByName("email")[0].value;
    var domain = document.getElementsByName("domain")[0].value;
    var fullEmail = email + domain;
    createUser(fullEmail);
}
/*
 * Create a new address for user. If address is already specified it checks if that is valid 
 */
function createUser(address) {
    if($(window).width() < 1000) {
        $(".tmail-mobile-menu").fadeIn(100);
        $(".tmail-sidebar").hide(100);
    }
    $(".tmail-homepage").fadeOut(100);
    $(".tmail-body").fadeOut(100);
    $(".tmail-main").delay(100).fadeIn();
    $(".tmail-loader").delay(100).fadeIn();
    $.get("user.php", {
        user: address
    }).done(function (data) {
        address = data;
        $("#current-tmail-id").html(address);
        if(isEncode === "yes") {
            var newAddress = btoa(address);
            hasher.setHash(newAddress);
        } else {
            hasher.setHash(address);
        }
        if (!$("#tmail-switcher-list-ul:contains('"+address+"')").length) {
            var tagToAdd = "<li onclick=\"createUser('"+address+"')\"><a>"+address+"</a></li>";
            $("#tmail-switcher-list-ul").append(tagToAdd);
        }
        $.get("mail.php", function (data) {
            $("#tmail-data").html('');
            if (data) {
                var splitData = data.split('<-----TMAILNEXTMAIL----->');
                $.each(splitData, function (index, value) {
                    value = $.trim(value);
                    if (value.length > 0) {
                        var internalSplitData = value.split('<-----TMAILCHOPPER----->');
                        $("#tmail-data").append(internalSplitData[0]);
                        $(".tmail-email-body").append(internalSplitData[1]);
                    }
                });
            }
            checkEmptyEmailList();
            retriveNewMails();
            $(".tmail-main").fadeOut()
            $(".tmail-body").delay(400).fadeIn();
            saveEMails();
            $(".tmail-email-body a").attr("target","_blank");
            scrollTmailList.update();
            scrollTmailBody.update();
            scrollSidebar.update();
            $(".tmail-email-content-li").fadeOut(100);
            $(".tmail-email-body-placeholder").delay(500).fadeIn();
        });
    });
}
/*
 * Checks for new emails at regular interval. setTimeout calls function every 1000 ms (1 Second)
 */
function retriveNewMails() {
    $.get("mail.php?unseen=1", function (data) {
        if (data.trim() === "DIE") {
            location.reload();
            return;
        } else {
            if (data) {
				if(data.indexOf("Fatal error: Uncaught exception 'PhpImap") != -1){
					location.reload(true);
				}
                var splitData = data.split('<-----TMAILNEXTMAIL----->');
                $.each(splitData, function (index, value) {
                    if (value.trim().length > 0) {
                        var internalSplitData = value.split('<-----TMAILCHOPPER----->');
                        $("#tmail-data").prepend(internalSplitData[0]);
                        $(".tmail-email-body").prepend(internalSplitData[1]);
                        alignElements();
                    }
                });
                checkEmptyEmailList();
                $(".tmail-email-body a").attr("target","_blank");
                notifyUser("You got some new EMails",true);
            }
            currentRefreshRate = refreshRate;
            t = setInterval(updateTimer, 1000);
        }
    });
}

function alignElements() {
    var docWidth = $(window).width();
    if (docWidth < 1000) {
        $(".tmail-sidebar").fadeOut(100);
        $(".tmail-email-body").fadeOut(100);
    } else {
        var sidebarWidth = $(".tmail-sidebar").width();
        if (sidebarWidth < 200) {
            $(".tmail-sidebar").fadeOut(100);
            if ($(".tmail-email-body").hasClass("col-lg-6")) {
                $(".tmail-email-body").removeClass("col-lg-6").addClass("col-lg-8");
            }
        } else {
            $(".tmail-sidebar").show();
            if ($(".tmail-email-body").hasClass("col-lg-8")) {
                $(".tmail-email-body").removeClass("col-lg-8").addClass("col-lg-6");
            }
        }
        var listWidth = $(".tmail-list").width();
        if (listWidth < 306) {
            $(".tmail-email-body").fadeOut(100);
        } else {
            $(".tmail-email-body").show();
        }
    }
}

$(window).resize(function () {
    alignElements();
});

$(".tmail-list-ul").click(function () {
    var docWidth = $(window).width();
    if (docWidth < 1000) {
        $(".tmail-list").fadeOut(100);
        $(".tmail-email-body").fadeIn();
        $(".tmail-mobile-menu i.fa-bars").fadeOut(100);
        $(".tmail-mobile-menu i.fa-chevron-left").delay(100).fadeIn();
    }
    $(".tmail-email-body-placeholder").fadeOut(100);
});

$(".tmail-mobile-menu i.fa-chevron-left").click(function () {
    $(".tmail-list").fadeIn();
    $(".tmail-email-body").fadeOut(100);
    $(".tmail-mobile-menu i.fa-chevron-left").fadeOut(100);
    $(".tmail-mobile-menu i.fa-bars").delay(100).fadeIn();
    $(".tmail-email-body").css("z-index","-1");
});

$(".tmail-mobile-menu i.fa-bars").click(function () {
    $(".tmail-list").fadeOut(100);
    $(".tmail-sidebar").fadeIn();
    $(".tmail-mobile-menu i.fa-bars").fadeOut(100);
    $(".tmail-mobile-menu i.fa-times").delay(100).fadeIn();
});

$(".tmail-mobile-menu i.fa-times").click(function () {
    $(".tmail-list").fadeIn();
    $(".tmail-sidebar").fadeOut(100);
    $(".tmail-mobile-menu i.fa-times").fadeOut(100);
    $(".tmail-mobile-menu i.fa-bars").delay(100).fadeIn();
});

/*
 * To show TMail Complete EMail
 */
function showTMailBody(mailContentID) {
    $(".tmail-email-content-li").fadeOut(100);
    $("#tmail-email-body-content-" + mailContentID).fadeToggle();
    $(".tmail-list-ul li").removeClass("tmail-list-active");
    $("#tmail-email-list-" + mailContentID).addClass("tmail-list-active");
    $(".tmail-email-body").css("z-index","1");
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
    notifyUser("EMail ID copied to clipboard");
}

/*
 * 
 */
function notifyUser(message, sendPush = false) {
    var x = document.getElementById("snackbar");
    x.innerHTML = message;
    x.className = "show";
    setTimeout(function () {
        x.className = x.className.replace("show", "");
    }, 3000);
    if(pushNotifications && sendPush) {
    	if (Notification.permission === "granted") {
            var notification = new Notification(message);
        } else if (Notification.permission !== 'denied') {
            Notification.requestPermission(function(permission) {
                if (permission === "granted") {
                    var notification = new Notification(message);
                }
            });
        }
    }
}

/* 
 * Search Bar 
 */
(function () {
    var searchTerm, panelContainerId;
    $.expr[':'].containsCaseInsensitive = function (n, i, m) {
        return jQuery(n).text().toUpperCase().indexOf(m[3].toUpperCase()) >= 0;
    };
    $('#tmail-search').on('change keyup paste click', function () {
        searchTerm = $(this).val();
        $('#tmail-data > .tmail-email-list-li').each(function () {
            panelContainerId = '#' + $(this).attr('id');
            $(panelContainerId + ':not(:containsCaseInsensitive(' + searchTerm + '))').fadeOut(100);
            $(panelContainerId + ':containsCaseInsensitive(' + searchTerm + ')').show();
        });
    });
}());

/*
 * Function for saving email in Cookie
 */
function saveEMails() {
    $.get("actions.php?action=saveEMails", function (data) {
        
    });
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
 * Function to check if list is empty 
 */
function checkEmptyEmailList() {
    var emptyCheck = $('#tmail-data').html().trim();
    if (emptyCheck === "") {
        $(".tmail-list-placeholder").fadeIn();
    } else {
        $(".tmail-list-placeholder").fadeOut();
    }
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
    notifyUser("File Ready! Please hit okay / save if you got a popup");
    return false;
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
    var mailLocator = "#tmail-email-list-".concat(mailid);
    $(mailLocator).hide( "400", function() {
        $( this ).remove();
        $(".tmail-email-content-li").fadeOut(100);
        $(".tmail-email-body-placeholder").delay(500).fadeIn();
        $("#tmail-email-body-content-"+mailid).delay(500).remove();
        checkEmptyEmailList();
    });
    notifyUser("TMail Deleted!");
    return false;
}

/*
 * Function to change language
 */
function setLang() {
    var setLang = document.getElementsByName("lang")[0].value;
    $(".tmail-homepage").fadeOut();
    $(".tmail-body").fadeOut();
    $(".tmail-main").delay(400).fadeIn();
    if ( setLang === "hi" ) {
        $(".inner-loader span").html("रुकिए");
    } else if ( setLang === "fr" ) {
        $(".inner-loader span").html("Chargement");
    } else if ( setLang === "ch" ) {
        $(".inner-loader span").html("载入中");
    } else if ( setLang === "ar" ) {
        $(".inner-loader span").html("جار التحميل");
    } else if ( setLang === "sp" ) {
        $(".inner-loader span").html("Cargando");
    } else if ( setLang === "ru" ) {
        $(".inner-loader span").html("загрузка");
    } else if ( setLang === "de" ) {
        $(".inner-loader span").html("Bezig met laden");
    } else if ( setLang === "pl" ) {
        $(".inner-loader span").html("Ładuję");
    } else {
        $(".inner-loader span").html("Loading");
    }
    $(".tmail-loader").delay(600).fadeIn();
    $.get( "actions.php", { action: "changeLang", lang: setLang } ).done(function( data ) { location.reload(); });
}

/*
 * Deleting old attachments
 */
function deleteAttachments() {
    $.get("actions.php", {
        action: 'deleteOldAttachments'
    });
}