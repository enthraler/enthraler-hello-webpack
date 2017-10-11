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

/**
	Haxe JS Enthraler Component.

	We define `Hello` as the class to export in build.hxml.
	Enthraler components need an AMD definition, and if you implement the `HaxeTemplate` class, it will generate an AMD definition for you.

	It will also take care of loading dependencies if you add `@:enthralDependency('amdPath', HaxeExtern)`.
	Note: the macro will overwrite the `@:native` metadata on any externs to a custom global variable, and set that variable during the define function.
**/
@:enthralerDependency('cdnjs/d3/3.5.17/d3.min', D3)
@:enthralerDependency('cdnjs/d3-tip/0.7.1/d3-tip.min', D3Tip)
class AgreeOrDisagree implements HaxeTemplate<AuthorData> {
	// Visualisation config
	var width = 960;
	var height = 500;
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
		question: ParagraphElement,
		demograph: ParagraphElement,
		radius: ParagraphElement,
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
		this.labels = {
			question: document.createParagraphElement(),
			demograph: document.createParagraphElement(),
			radius: document.createParagraphElement(),
		}
		environment.container.appendChild(labels.question);
		environment.container.appendChild(labels.demograph);
		environment.container.appendChild(labels.radius);

		this.environment = environment;
	}

	public function render(plainJsonData: {}) {
		// Enthraler will have done a plain JSON.parse() rather than using tink.Json.parse()
		// We need to re-parse it if we want it to support our enums correctly.
		var jsonStr = haxe.Json.stringify(plainJsonData);
		this.authorData = tink.Json.parse(jsonStr);
		this.setDemographicQuestion(0);
		this.drawTheDots();
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
			.select("body")
			.append("svg")
			.attr("width", width)
			.attr("height", height);

		updateCircles();

		force
			.gravity(0)
			.charge(0)
			.on("tick", tick)
			.start();

		var q = 0;
		window.addEventListener('keydown', function (e) {
			switch e.keyCode {
				case 37:
					// Left
					showQuestion(q--);
				case 39:
					// Right
					showQuestion(q++);
				case 82:
					// "r" for radius
					toggleRadiusScaling(!this.allowRadiusScaling);
				case other:
					trace('Keycode ${other} is not assigned to any action');
			}
		});

		// Resize the iframe to fit the new height.
		environment.requestHeightChange();
	}

	function showQuestion(questionIndex: Null<Int>) {
		this.questionIndex = questionIndex;
		var question = this.authorData.questions[questionIndex],
			label = (questionIndex != null) ? 'Question: ${question.question}' : 'Survey';
		this.labels.question.innerText = '$label (<-- or -->)';
		reRender();
	}

	function toggleRadiusScaling(allow: Bool) {
		this.allowRadiusScaling = allow;
		this.labels.radius.innerText = 'Radius scaling ${allow ? "on" : "off"} ("r")';
		reRender();
	}

	function setDemographicQuestion(questionNumber: Int) {
		this.demographicQuestionIndex = questionNumber;
		var groupsInQuestion = getGroupsInQuestion(questionNumber);
		this.color = D3.scale.category10().domain(D3.range(groupsInQuestion.length));
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
					for (respondant in authorData.responses) {
						var response = respondant[questionIndex];
					}
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
				responseText = respondant[questionIndex],
				response = getResponse(responseText),
				groupIndex = allGroups.indexOf(response.group),
				demographQuestion = this.authorData.questions[demographicQuestionIndex],
				demographText = respondant[demographicQuestionIndex],
				groupsInDemographicQuestion = getGroupsInQuestion(demographicQuestionIndex),
				demographIndex = groupsInDemographicQuestion.indexOf(demographText);

			node.cx = xScale.call(groupIndex);
			node.radius = this.allowRadiusScaling
				? Math.sqrt(response.radius) * maxRadius
				: maxRadius;
			node.tooltip = '$responseText [$demographText]';
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
