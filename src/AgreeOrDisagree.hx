import enthraler.HaxeTemplate;
import enthraler.Environment;
import js.d3.D3;
import js.d3.scale.Scale;
import js.d3.selection.Selection;
import js.d3.layout.Layout;
import js.Browser.*;
import js.html.*;
import tink.Json;

typedef CsvData = Array<Array<String>>;

typedef ResponseGroups = Array<{value: String, group: String, radius: Int}>

typedef Question = {
    question: String,
    type: QuestionType
}

enum QuestionType {
    GroupedAnswer;
    GroupedWeightedAnswer(groups: ResponseGroups);
    FreeText;
}

typedef AuthorData = {
    /**
    Column numbers that contain profile info.
    First row should be a header with the column titles.
    **/
    var profileInfo: Array<Int>;
    /**
    The list of questions we are asking.
    See tink_json for how these are displayed in JSON form: https://github.com/haxetink/tink_json#enums
    **/
    var questions: Array<Question>;
    /**
    All the survey responses.
    An Array of CSV rows, containing an Array of CSV column values.
    In this rows should represent each respondant, columns each question, and cells each individual response.
    The first row should be the header with the question title.
    **/
    var responses: CsvData;
}

typedef CircleNode = {
	responseIndex: Int,
	radius: Float,
	color: String,
	tooltip: String,
	?x: Float,
	?y: Float,
	cx: Float,
	cy: Float,
};

extern class D3Tip {

}

extern class Hammer {
	function new(elm: Element, options: {});
	function on(event: String, callback: haxe.Constraints.Function): Void;
}

/**
	Haxe JS Enthraler Component.

	We define `Hello` as the class to export in build.hxml.
	Enthraler components need an AMD definition, and if you implement the `HaxeTemplate` class, it will generate an AMD definition for you.

	It will also take care of loading dependencies if you add `@:enthralDependency('amdPath', HaxeExtern)`.
	Note: the macro will overwrite the `@:native` metadata on any externs to a custom global variable, and set that variable during the define function.
**/
@:enthralerDependency('cdnjs/d3/3.5.17/d3.min', D3)
//@:enthralerDependency('cdnjs/d3-tip/0.7.1/d3-tip.min', D3Tip)
@:enthralerDependency('cdnjs/hammer.js/2.0.8/hammer.min', Hammer)
@:enthralerDependency('css!agreeOrDisagree.css')
@:enthralerDependency('css!cdnjs/font-awesome/4.7.0/css/font-awesome.css')
class AgreeOrDisagree implements HaxeTemplate<AuthorData> {
	// Visualisation config
	var width = 650;
	var height = 300;
	var padding = 6;
	var minRadius = 4;
	var maxRadius = 12;
	var numberOfNodes(get, null): Int;
	var numberOfClusters: Int;

	function get_numberOfNodes(): Int {
		return this.authorData.responses.length;
	}

	// Enthraler stuff
	var environment: Environment;
	var authorData: AuthorData;
	var labels: {
		title: Element,
		question: Element,
		demograph: Element,
		radius: InputElement,
	};
	var allowRadiusScaling: Bool;
	var questionIndex: Null<Int>;
	var demographicQuestionIndex: Null<Int>;

	// D3 stuff
	var svg: Selection;
	var circle: Selection;
	var nodes: Array<CircleNode>;
	var xScale: Ordinal;
	var color: Ordinal;
	var force: Force; // See https://github.com/d3/d3-3.x-api-reference/blob/master/Force-Layout.md

	public function new(environment:Environment) {
		environment.container.innerHTML = '<div id="ui-container">
			<h1 id="title"></h1>
			<div id="settings">
				<select><option id="demograph-label"></option></select>
				<div>
					<label for="radius-toggle" title="If a respondant rated a question as important, we will make their circle bigger">
						Show loud voices
						<input type="checkbox" id="radius-toggle" checked />
					</label>
				</div>
			</div>
			<div id="d3-container"></div>
			<div id="question-nav">
				<a href="#" id="previous-btn"><i class="fa fa-chevron-left"></i><span class="sr-only">Previous Question</span></a>
				<h2 id="question-label"></h2>
				<a href="#" id="next-btn"><i class="fa fa-chevron-right"></i><span class="sr-only">Next Question</span></a>
			</div>
		</div>';
		this.labels = {
			title: document.getElementById("title"),
			question: document.getElementById("question-label"),
			demograph: document.getElementById("demograph-label"),
			radius: cast document.getElementById("radius-toggle"),
		};

		this.environment = environment;
		this.color = D3.scale.category10().domain(D3.range(1));
	}

	public function render(plainJsonData: {}) {
		// Enthraler will have done a plain JSON.parse() rather than using tink.Json.parse()
		// We need to re-parse it if we want it to support our enums correctly.
		var jsonStr = haxe.Json.stringify(plainJsonData);
		this.authorData = tink.Json.parse(jsonStr);
		labels.title.innerText = 'Steam Community Survey';
		this.drawTheDots();
		this.setDemographicQuestion(null);
		this.toggleRadiusScaling(true);
		this.showQuestion(null);

		environment.requestHeightChange();
	}

	function setNumberOfGroups(num: Int) {
		this.numberOfClusters = num;
		this.xScale = D3.scale
			.ordinal()
			.domain(D3.range(num))
			.rangePoints([0, width], 1);
	}

    function drawTheDots() {
		setNumberOfGroups(1);

		this.nodes = D3.range(numberOfNodes).map(function(index): CircleNode {
			var i = Math.floor(Math.random() * numberOfClusters),
				v = (i + 1) / numberOfClusters * -Math.log(Math.random());
			return {
				responseIndex: index,
				radius: maxRadius,
				color: ''+color.call(i),
				tooltip: '',
				cx: xScale.call(i),
				cy: height / 2
			};
		});

		this.force = D3.layout
			.force()
			.nodes(nodes)
			.size([width, height]);

		this.svg = D3
			.select("#d3-container")
			.append("svg")
			.attr("width", width)
			.attr("height", height)
			.attr("viewBox", [].join(','));

		updateCircles();

		force
			.gravity(0)
			.charge(0)
			.on("tick", tick)
			.start();

		var q = -1,
			demographicQuestions = [null, 0, 42, 43, 44, 45, 46, 47];

		function prevQuestion() if (q > 0) showQuestion(--q);
		function nextQuestion() if (q < (authorData.questions.length - 1)) showQuestion(++q);

		window.addEventListener('keydown', function (e) {
			switch e.keyCode {
				case 37:
					// Left
					prevQuestion();
				case 39:
					// Right
					nextQuestion();
				case 38:
					// Up
					var currentIndex = demographicQuestions.indexOf(this.demographicQuestionIndex),
						prevIndex = (currentIndex<1) ? (demographicQuestions.length-1) : currentIndex-1;
					this.setDemographicQuestion(demographicQuestions[prevIndex]);
					e.preventDefault();
				case 40:
					// Down
					var currentIndex = demographicQuestions.indexOf(this.demographicQuestionIndex),
						nextIndex = (currentIndex==(demographicQuestions.length-1)) ? 0 : currentIndex+1;
					this.setDemographicQuestion(demographicQuestions[nextIndex]);
					e.preventDefault();
				case 82:
					// "r" for radius
					toggleRadiusScaling(!this.allowRadiusScaling);
				case other:
					trace('Keycode ${other} is not assigned to any action');
			}
		});

		document
			.getElementById("previous-btn")
			.addEventListener("click", prevQuestion);

		document
			.getElementById("next-btn")
			.addEventListener("click", nextQuestion);

		var hammer = new Hammer(environment.container, null);
		hammer.on('swiperight', prevQuestion);
		hammer.on('swipeleft', nextQuestion);

		labels.radius.addEventListener('change', function (e) {
			this.toggleRadiusScaling(labels.radius.checked);
		});

		// Resize the iframe to fit the new height.
		environment.requestHeightChange();
	}

	function showQuestion(questionIndex: Null<Int>) {
		this.questionIndex = questionIndex;
		var question = this.authorData.questions[questionIndex],
			label = (questionIndex != null) ? question.question : 'Survey';
		this.labels.question.innerText = label;
		reRender();
	}

	function toggleRadiusScaling(allow: Bool) {
		this.allowRadiusScaling = allow;
		reRender();
	}

	function setDemographicQuestion(questionNumber: Null<Int>) {
		this.demographicQuestionIndex = questionNumber;
		var numGroups,
			label;
		if (questionNumber != null) {
			var groupsInQuestion = getGroupsInQuestion(questionNumber);
			numGroups = groupsInQuestion.length;
			label = this.authorData.questions[questionNumber].question;
		} else {
			numGroups = 1;
			label = 'No demograph selected';
		}
		this.labels.demograph.innerText = 'Coloring: ' + label;
		this.color = D3.scale.category10().domain(D3.range(0, numGroups - 1));
		reRender();
	}

	function reRender() {
		updateNodes();
		updateCircles();
	}

	function getGroupsInQuestion(questionIndex) {
		var allGroups = [],
			question = this.authorData.questions[questionIndex];

		function addGroup(name: String) {
			if (allGroups.indexOf(name) == -1) allGroups.push(name);
		}

		if (question != null) {
			switch question.type {
				case GroupedAnswer:
					for (respondant in authorData.responses) {
						var response = respondant[questionIndex];
						addGroup(response);
					}
				case GroupedWeightedAnswer(groups):
					for (group in groups) {
						addGroup(group.group);
					}
				case FreeText:
			}

		} else {
			addGroup('Everyone');
		}

		return allGroups;
	}

	function updateNodes() {
		var allGroups = getGroupsInQuestion(questionIndex),
			getResponse:String->{group: String, radius: Int},
			question = this.authorData.questions[questionIndex];

		if (question != null) {
			switch question.type {
				case GroupedAnswer:
					getResponse = function (response: String) return {group: response, radius: 1};
				case GroupedWeightedAnswer(groups):
					getResponse = function (response) {
						for (group in groups) {
							if (group.value == response) {
								return group;
							}
						}
						return {group: 'Unanswered', radius: 0};
					}
				case FreeText:
					trace('not handling free text yet');
					return;
			}

		} else {
			getResponse = function (_) {
				return {group: 'Everyone', radius: 1};
			}
		}
		setNumberOfGroups(allGroups.length);

		nodes = nodes.map(function(node) {
			var respondant = this.authorData.responses[node.responseIndex],
				responseText = respondant[questionIndex];
			if (responseText == "") {
				node.radius = 0;
				node.cx = -1;
				return node;
			}
			var response = getResponse(responseText),
				groupIndex = allGroups.indexOf(response.group),
				demographText = respondant[demographicQuestionIndex],
				groupsInDemographicQuestion = getGroupsInQuestion(demographicQuestionIndex),
				demographIndex = groupsInDemographicQuestion.indexOf(demographText);

			node.cx = xScale.call(groupIndex);
			// TODO: figure out a way to do radius as a ratio of the maximum value.
			node.radius = this.allowRadiusScaling
				? (response.radius / 3) * maxRadius
				: maxRadius/3;
			node.tooltip = responseText;
			if (demographText != null) {
				node.tooltip += ' [$demographText]';
			}
			node.color = ''+color.call(demographIndex);
			return node;
		});
	}

	function updateCircles() {
		// Update current, circles
		this.circle = svg.selectAll("circle")
			.data(nodes)
			.attr("r", function(d) {
				return d.radius;
			})
			.style("fill", function(d) {
				return d.color;
			});

		// Add missing circles
		circle.enter()
			.append("circle")
			.attr("r", function(d) {
				return d.radius;
			})
			.style("fill", function(d) {
				return d.color;
			})
			// Note, we are casting to dynamic to avoid Haxe binding `force.drag` to `force`.
			// In this case we actually want JS's super weird behaviour of making "this" bind to whatever the hell it's attached to when it's called.
			.call((force:Dynamic).drag)
			.append("title");

		// Add a tooltip
		this.circle
			.select("title")
			.text(function (d: CircleNode) {
				return d.tooltip;
			});

		// Delete circles that no longer need to be here
		circle.exit().remove();

		// Re-trigger the momentum on the gravity.
		this.force.resume();
	}

	// Move nodes toward cluster focus.
	function gravity(alpha: Float) {
		return function(d: CircleNode) {
			d.y += (d.cy - d.y) * alpha;
			d.x += (d.cx - d.x) * alpha;
		};
	}

	function collide(alpha: Float) {
		var quadtree = D3.geom.quadtree(nodes);
		return function(d: CircleNode) {
			var r = d.radius + maxRadius + padding,
				nx1 = d.x - r,
				nx2 = d.x + r,
				ny1 = d.y - r,
				ny2 = d.y + r;
			quadtree.visit(function(quad, x1, y1, x2, y2) {
				var point: CircleNode = quad.point;
				if (point != null && point != d) {
					var x = d.x - point.x,
						y = d.y - point.y,
						l = Math.sqrt(x * x + y * y),
						isSameGroup = (d.cx == point.cx), //(d.color != point.color),
						r =
							d.radius +
							point.radius +
							(isSameGroup ? 1 : padding);
					if (l < r) {
						l = (l - r) / l * alpha;
						d.x -= x *= l;
						d.y -= y *= l;
						point.x += x;
						point.y += y;
					}
				}
				return x1 > nx2 || x2 < nx1 || y1 > ny2 || y2 < ny1;
			});
		};
	}

	function tick(e) {
		if (this.circle == null) {
			throw new js.Error('circle is null');
		}
		this.circle
			.each(gravity(0.2 * e.alpha))
			.each(collide(0.5))
			.attr("cx", function(d) {
				return d.x;
			})
			.attr("cy", function(d) {
				return d.y;
			})
			// Jason: Added "r" and "fill" in the hope of rendering an update.
			.attr("r", function(d) {
				return d.radius;
			})
			.style("fill", function(d) {
				return d.color;
			});
	}
}


typedef AgreeOrDisagreeProps = {
	name:String
};
