/**
 * Created by Noisky on 17/05/13.
 * Revised by Noisky on 19/09/10.
 */
$(document).ready(function () {
    /**
     * 随机获取背景图片
     */
    var bgNum = 10; // 定义随机数范围 1-10 和图片数量保持一致
    var randomNum = Math.floor(Math.random() * bgNum) + 1;
    // 拼接图片地址
    var imgUrl = '//gcore.jsdelivr.net/gh/ldxw/cdn@master/static/Homepage/Noisky_files/img/background-image/bg-' + randomNum + '.jpg';
    // 替换页面中的背景图片地址
    $("header").css("background-image", "url(" + imgUrl + ")");

    /**
     * 移动端下拉菜单栏
     */
    var nw = $('.navigation-wrapper');

    // 定义菜单关闭事件
    function bounceOutUp() {
        nw.on(function () {
            nw.toggleClass('visible animated bounceOutUp');
        });
        nw.toggleClass('animated bounceInDown animated bounceOutUp');
    }

    // 根据菜单状态定义单击的操作
    $('.btn-mobile-menu').click(function () {
        if (nw.css('display') === "block") {
            bounceOutUp();
        } else {
            nw.toggleClass('visible animated bounceInDown');
        }
        $('.btn-mobile-menu_icon').toggleClass('fa fa-list fa fa-angle-up animated fadeIn');
    });
    // 点击下拉菜单以外的其他标签区域收起菜单生效
    $(".panel-main").on('click', ':not(.mobile,.btn-mobile-menu,.navigation-wrapper)', function () {
        if (nw.hasClass("bounceInDown")) {
            bounceOutUp();
            $('.btn-mobile-menu_icon').toggleClass('fa fa-list fa fa-angle-up animated fadeIn');
        }
    });
    // 阻止冒泡事件执行
    nw.click(function (event) {
        event.stopPropagation();
    });
    /**
     * 底部年份动态化
     */
    $('.year').html(new Date().getFullYear());

    /**
     * 异步加载一言
     */
    (function getHitokoto() {
        $.ajax({
            //url: "https://api.imjad.cn/hitokoto/?encode=jsc&charset=utf-8&length=50",
            url: "https://v1.hitokoto.cn/?encode=json&charset=utf-8",
            dataType: "jsonp",
            async: true,
            jsonp: "callback",
            jsonpCallback: "hitokoto",
            success: function (result) {
                $('#hitokoto').html("<p>" + result.hitokoto + "</p>")
            },
            error: function () {
                $('#hitokoto').html("<p>读取数据失败了的说……_(:з」∠)_</p>")
            }
        });
    })();
});
